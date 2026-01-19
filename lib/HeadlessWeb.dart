import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'anime_function.dart'; // 引用你的 AnimeApiService 以获取 headers

class HeadlessWeb {
  static HeadlessInAppWebView? _headlessWebView;
  static InAppWebViewController? _controller;

  // 当前任务的完成器
  static Completer<String>? _currentCompleter;

  // 标记是否正在初始化
  static bool _isInitializing = false;

  // 1. 初始化方法 (建议在 main.dart 的 main() 中调用，或者在首页加载时调用)
  static Future<void> init() async {
    if (_headlessWebView != null || _isInitializing) return;
    _isInitializing = true;

    print("🚀 正在预热全局 WebView...");

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      cacheEnabled: false, // 提取链接不需要缓存
      loadsImagesAutomatically: false, // 禁止图片
      userAgent: "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36", // 硬编码或从 Service 获取
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      // 关键：开启请求拦截，用于屏蔽垃圾资源
      useShouldInterceptRequest: true,
    );

    _headlessWebView = HeadlessInAppWebView(
      initialSettings: settings,
      onWebViewCreated: (controller) {
        _controller = controller;
        print("✅ 全局 WebView 初始化完成");
      },
      // 统一资源监听
      onLoadResource: (controller, resource) {
        _checkUrl(resource.url.toString());
      },
      // 统一错误监听
      onReceivedError: (controller, request, error) {
        // 很多视频链接会报错，这里也要检查
        _checkUrl(request.url.toString());
      },
      // 拦截无用资源，极大提升速度！
      shouldInterceptRequest: (controller, request) async {
        String url = request.url.toString().toLowerCase();

        // 放行视频流和关键API
        if (url.contains("mp4") || url.contains("m3u8") || url.contains("video")) {
          return null;
        }

        // 屏蔽 CSS, 图片, 字体, 统计脚本等
        if (url.contains(".css") ||
            url.contains(".jpg") ||
            url.contains(".png") ||
            url.contains(".gif") ||
            url.contains(".woff") ||
            url.contains("google-analytics") ||
            url.contains("hm.baidu")) {
          // 返回空的响应，直接阻断网络请求
          return WebResourceResponse(contentType: "text/plain", data: null);
        }
        return null;
      },
    );

    await _headlessWebView?.run();
    _isInitializing = false;
  }

  // 2. 检查 URL 是否为视频
  static void _checkUrl(String url) {
    if (_currentCompleter == null || _currentCompleter!.isCompleted) return;
    if (url.isEmpty) return;

    // 视频特征匹配 (根据实际情况补充)
    bool isVideo = false;
    if (url.startsWith('http')) {
      if (url.contains('.mp4') || url.contains('.m3u8')) isVideo = true;
      else if (url.contains('video/tos')) isVideo = true; // TikTok
      else if (url.contains('akamaized.net') && url.contains('/video/')) isVideo = true;
      else if (url.contains('douyin')) isVideo = true;
    }

    if (isVideo) {
      print("⚡ 极速提取成功: $url");
      _currentCompleter?.complete(url);
    }
  }

  // 3. 执行提取任务
  static Future<String> fetchVideoUrl(String pageUrl) async {
    // 确保已初始化
    if (_headlessWebView == null) {
      await init();
    }

    // 如果上一个任务还没结束，强制取消，优先处理当前任务
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete("");
    }

    _currentCompleter = Completer<String>();

    try {
      print("开始加载页面 (复用WebView): $pageUrl");

      // 先停止之前的加载
      await _controller?.stopLoading();
      // 加载空白页清除上下文 (可选，视情况而定)
      // await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri("about:blank")));

      // 加载新页面
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(pageUrl)));

      // 同时启动 JS 轮询作为保底
      _startJsPolling();

      // 设置超时
      return await _currentCompleter!.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print("⚠️ 提取超时");
            _controller?.stopLoading(); // 停止加载节省资源
            return "";
          }
      );
    } catch (e) {
      print("提取异常: $e");
      return "";
    }
    // 注意：这里不再 dispose WebView，留给下次用
  }

  // JS 轮询保底
  static void _startJsPolling() async {
    int retry = 0;
    while (retry < 10) {
      if (_currentCompleter == null || _currentCompleter!.isCompleted) break;
      await Future.delayed(Duration(milliseconds: 800));

      if (_controller != null) {
        String jsCode = """
          (function() {
            var v = document.querySelector('video');
            if(v && v.src && v.src.startsWith('http')) return v.src;
            var s = document.querySelector('source');
            if(s && s.src && s.src.startsWith('http')) return s.src;
            return "";
          })();
        """;
        try {
          var res = await _controller?.evaluateJavascript(source: jsCode);
          if (res != null && res.toString().startsWith("http")) {
            _checkUrl(res.toString());
          }
        } catch (_) {}
      }
      retry++;
    }
  }
}
