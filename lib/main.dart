import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController controller;
  bool isLoading = true;
  bool isDownloading = false;
  DateTime? lastBackPress;

  @override
  void initState() {
    super.initState();

    if (Platform.isAndroid) {
      AndroidWebViewController.enableDebugging(true);
    }

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      // Debug channel - also handles download messages in case web uses this channel
      ..addJavaScriptChannel(
        'FlutterDebug',
        onMessageReceived: (message) {
          // Try to parse as download command first
          if (_handleFlutterChannelMessage(message.message)) {
            return; // Was a download command, handled
          }
          // Otherwise show as debug message (only for non-JSON messages)
          if (!mounted) return;
          if (!message.message.startsWith('{')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message.message),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      )
      // FlutterChannel for web-to-app communication (download requests)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) {
          _handleFlutterChannelMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Intercept PDF download URLs
            if (request.url.contains('/api/member-card/export')) {
              _downloadPdf(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse('https://trisakti.digitalforte.id'));

    if (Platform.isAndroid) {
      final androidController = controller.platform as AndroidWebViewController;

      // Handle file picker for photo uploads
      androidController.setOnShowFileSelector((params) async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );

        if (result == null || result.files.single.path == null) {
          return [];
        }

        final filePath = result.files.single.path!;
        return [Uri.file(filePath).toString()];
      });
    }
  }

  /// Handle messages from web via FlutterChannel.postMessage()
  /// Returns true if message was a valid download command
  bool _handleFlutterChannelMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final url = data['url'] as String?;

      if (type == 'download_member_card' && url != null) {
        _downloadPdf(url);
        return true;
      }
    } catch (e) {
      debugPrint('Error parsing FlutterChannel message: $e');
    }
    return false;
  }

  /// Get Downloads folder path (works on all Android devices)
  Future<String> _getDownloadsPath() async {
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        // Navigate from app external dir to Downloads
        // Path: /storage/emulated/0/Android/data/com.app/files -> /storage/emulated/0/Download
        final downloadsDir = Directory(
          '${extDir.parent.parent.parent.parent.path}/Download',
        );
        if (await downloadsDir.exists()) {
          return downloadsDir.path;
        }
      }
    } catch (e) {
      debugPrint('Error getting downloads path: $e');
    }
    // Fallback to standard Android path
    return '/storage/emulated/0/Download';
  }

  /// Download PDF and open it after download
  Future<void> _downloadPdf(String url) async {
    if (isDownloading) return;

    setState(() => isDownloading = true);

    // Show download progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            const Expanded(child: Text('Downloading Member Card...')),
          ],
        ),
      ),
    );

    try {
      final response = await http.get(Uri.parse(url));
      final contentType = response.headers['content-type'];

      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      if (response.statusCode != 200) {
        _showMessage('Download gagal: Server error (${response.statusCode})');
        return;
      }

      if (contentType == null || !contentType.contains('application/pdf')) {
        _showMessage('Download gagal: File bukan PDF');
        return;
      }

      // Save to public Downloads folder (visible in file manager)
      final fileName =
          'member_card_${DateTime.now().millisecondsSinceEpoch}.pdf';

      // Get Downloads path dynamically (works on all Android devices)
      final downloadsPath = await _getDownloadsPath();
      final file = File('$downloadsPath/$fileName');
      await file.writeAsBytes(response.bodyBytes);

      // Show success message with option to open
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Member Card tersimpan di folder Download!\n$fileName',
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'BUKA',
              onPressed: () => _openFile(file.path),
            ),
          ),
        );
      }

      // Auto open the file
      await _openFile(file.path);
    } catch (e) {
      // Close progress dialog if still showing
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      _showMessage('Download gagal: ${e.toString()}');
    } finally {
      setState(() => isDownloading = false);
    }
  }

  /// Open file using system default app
  Future<void> _openFile(String filePath) async {
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      _showMessage('Tidak bisa membuka file: ${result.message}');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleBack() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return;
    }

    final now = DateTime.now();
    if (lastBackPress == null ||
        now.difference(lastBackPress!) > const Duration(seconds: 2)) {
      lastBackPress = now;
      _showMessage('Tekan sekali lagi untuk keluar');
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}
