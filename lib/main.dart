import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
      ..addJavaScriptChannel(
          'FlutterDebug',
          onMessageReceived: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message.message),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.contains('/api/member-card/export')) {
              downloadPdf(request.url);
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
      final androidController =
          controller.platform as AndroidWebViewController;

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

  Future<void> downloadPdf(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      final contentType = response.headers['content-type'];

      if (response.statusCode != 200 ||
          contentType == null ||
          !contentType.contains('application/pdf')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal: response bukan PDF')),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/member_card_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      await file.writeAsBytes(response.bodyBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF tersimpan: ${file.path}')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal download PDF')),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
