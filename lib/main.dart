import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';

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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => isLoading = true),
          onPageFinished: (_) => setState(() => isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse('https://trisakti.digitalforte.id'));

    if (Platform.isAndroid) {
      final androidController = controller.platform as AndroidWebViewController;

      androidController.setOnShowFileSelector((params) async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
      
        if (result == null || result.files.single.bytes == null) {
          return [];
        }
      
        final file = result.files.single;
        final base64 = base64Encode(file.bytes!);
        final name = file.name;
        final ext = name.split('.').last.toLowerCase();
      
        final mime = ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : ext == 'gif'
                    ? 'image/gif'
                    : 'image/jpeg';
      
        final js = '''
          (function() {
            const input = document.getElementById('photo_profile');
            if (!input) return;
      
            const binary = atob("$base64");
            const array = [];
            for (let i = 0; i < binary.length; i++) {
              array.push(binary.charCodeAt(i));
            }
      
            const blob = new Blob([new Uint8Array(array)], { type: "$mime" });
            const file = new File([blob], "$name", { type: "$mime" });
      
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            input.files = dataTransfer.files;
      
            input.dispatchEvent(new Event('change', { bubbles: true }));
          })();
        ''';
      
        await controller.runJavaScript(js);
      
        return [];
      });
    }
  }

  /// Handle back logic
  Future<void> _handleBack() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return;
    }

    final now = DateTime.now();
    if (lastBackPress == null ||
        now.difference(lastBackPress!) > const Duration(seconds: 2)) {
      lastBackPress = now;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tekan sekali lagi untuk keluar'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
            if (isLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
