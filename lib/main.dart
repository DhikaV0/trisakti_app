import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
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

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(

          // State Loading
          onPageStarted: (_) {
            setState(() => isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => isLoading = false);
          },

          // Request Download File
          onNavigationRequest: (request) {
            if (request.url.contains('download') ||
                request.url.contains('export') ||
                request.url.contains('pdf')) {
              _downloadFile(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse('https://trisakti.digitalforte.id'),
      );
  }

  // Logika Download File
  Future<void> _downloadFile(String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'download_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final filePath = '${dir.path}/$fileName';
  
      await Dio().download(url, filePath);
  
      if (!mounted) return;
  
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('File berhasil diunduh. Ketuk untuk membuka'),
          action: SnackBarAction(
            label: 'Buka',
            onPressed: () {
              OpenFilex.open(filePath);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal mengunduh file'),
        ),
      );
    }
  }

  // Logika Tombol Back
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
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
