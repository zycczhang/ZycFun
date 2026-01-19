import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';


// --- 新增：线路模型 ---
class RouteItem {
  final String name;
  final String url;
  RouteItem({required this.name, required this.url});
}

// 新增：搜索结果模型，包含当前页数据和是否有下一页
class SearchResult {
  final List<AnimeItem> items;
  final bool hasNextPage;
  SearchResult({required this.items, required this.hasNextPage});
}

// --- 数据模型 ---
class AnimeItem {
  final String title;
  final String imageUrl;
  final String note;
  final String url;
  // 新增：用于存储历史记录的详细进度信息 {sourceIndex, episodeName, positionSeconds}
  final Map<String, dynamic>? playbackInfo;

  AnimeItem({
    required this.title,
    required this.imageUrl,
    required this.note,
    required this.url,
    this.playbackInfo,
  });

  // 修改：保存时去除域名，只存相对路径
  Map<String, dynamic> toJson() {
    String saveUrl = url;
    // 获取当前配置的 BaseUrl
    String currentBaseUrl = AnimeApiService.baseUrl;

    // 如果 URL 包含当前的域名，则截取掉，只保留后面的路径 (如 /vod/detail/id/123.html)
    if (url.startsWith(currentBaseUrl)) {
      saveUrl = url.substring(currentBaseUrl.length);
    }

    return {
      'title': title,
      'imageUrl': imageUrl,
      'note': note,
      'url': saveUrl,
      // 保存进度信息
      if (playbackInfo != null) 'playbackInfo': playbackInfo,
    };
  }

  // 修改：读取时如果发现是相对路径，自动拼接当前最新的 BaseUrl
  factory AnimeItem.fromJson(Map<String, dynamic> json) {
    String loadUrl = json['url'] ?? "";

    // 如果是相对路径 (以 / 开头)，拼上最新的 baseUrl
    if (loadUrl.startsWith('/')) {
      loadUrl = "${AnimeApiService.baseUrl}$loadUrl";
    }

    return AnimeItem(
      title: json['title'] ?? "",
      imageUrl: json['imageUrl'] ?? "",
      note: json['note'] ?? "",
      url: loadUrl, // 内存中恢复为完整链接，供播放器使用
      playbackInfo: json['playbackInfo'],
    );
  }
}

class WeeklyData {
  final String day;
  final List<AnimeItem> items;
  WeeklyData({required this.day, required this.items});
}

class Episode {
  final String name;
  final String url;
  Episode({required this.name, required this.url});
}

class PlaySource {
  final String sourceName;
  final List<Episode> episodes;
  PlaySource({required this.sourceName, required this.episodes});
}

class AnimeDetail {
  final String title;
  final String imageUrl;
  final String introduction;
  final String updateTime;
  final List<PlaySource> playSources;
  AnimeDetail({required this.title, required this.imageUrl, required this.introduction, required this.updateTime, required this.playSources});
}

// --- 本地存储服务 ---
class AnimeStorageService {
  static const String _keyFavorites = 'anime_favorites';
  static const String _keyHistory = 'anime_history'; // 新增key
  static const String _keyBaseUrl = 'anime_base_url'; // 新增：保存BaseUrl的key

  // 保存选中的 BaseUrl
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }
  // 获取保存的 BaseUrl (如果为空则返回默认)
  static Future<String?> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl);
  }

  // 获取所有收藏
  static Future<List<AnimeItem>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_keyFavorites);
    if (jsonString == null) return [];

    List<dynamic> jsonList = jsonDecode(jsonString);
    // 这里调用 fromJson，会自动将相对路径转为当前域名的完整路径
    //print('🔍 获取到的原始收藏JSON数据: $jsonList');
    return jsonList.map((e) => AnimeItem.fromJson(e)).toList();
  }

  // [新增] 根据 URL 获取单条历史记录
  static Future<AnimeItem?> getHistoryItem(String url) async {
    final list = await getHistory();
    String targetPath = _getPath(url);
    try {
      // 查找路径匹配的第一条记录
      return list.firstWhere((e) => _getPath(e.url) == targetPath);
    } catch (e) {
      // 没找到
      return null;
    }
  }

  // 辅助方法：提取 URL 的路径部分 (忽略域名)
  // 比如 https://omofun03.top/vod/detail/123.html -> /vod/detail/123.html
  static String _getPath(String fullUrl) {
    try {
      if (fullUrl.startsWith('/')) return fullUrl; // 已经是相对路径
      Uri uri = Uri.parse(fullUrl);
      return uri.path;
    } catch (e) {
      return fullUrl;
    }
  }

  // 检查是否已收藏 (修改为比较路径)
  static Future<bool> isFavorite(String url) async {
    final list = await getFavorites();
    String targetPath = _getPath(url);
    // 只要路径相同就视为已收藏
    return list.any((item) => _getPath(item.url) == targetPath);
  }

  // 添加收藏
  static Future<void> addFavorite(AnimeItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();

    String targetPath = _getPath(item.url);

    // 避免重复添加 (比较路径)
    if (!list.any((e) => _getPath(e.url) == targetPath)) {
      list.add(item);
      // 保存时会自动调用 toJson 去除域名
      await prefs.setString(_keyFavorites, jsonEncode(list.map((e) => e.toJson()).toList()));
    }
  }

  // 取消收藏 (修改为比较路径)
  static Future<void> removeFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getFavorites();

    String targetPath = _getPath(url);
    list.removeWhere((item) => _getPath(item.url) == targetPath);

    await prefs.setString(_keyFavorites, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // --- 新增：历史记录功能 ---

  // 获取历史记录
  static Future<List<AnimeItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_keyHistory);
    if (jsonString == null) return [];
    List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((e) => AnimeItem.fromJson(e)).toList();
  }

  // 添加/更新历史记录
  static Future<void> addHistory(AnimeItem item) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnimeItem> list = await getHistory();

    String targetPath = _getPath(item.url);

    // 1. 如果已存在，先删除（为了把它移动到最上面）
    list.removeWhere((e) => _getPath(e.url) == targetPath);

    // 2. 插入到头部（最新的在最上面）
    list.insert(0, item);

    // 3. 限制数量为100
    if (list.length > 100) {
      list = list.sublist(0, 100);
    }

    // 4. 保存
    await prefs.setString(_keyHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // 可选：清空历史记录
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyHistory);
  }

  // 可选：删除单条历史记录
  static Future<void> removeHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    List<AnimeItem> list = await getHistory();
    String targetPath = _getPath(url);
    list.removeWhere((item) => _getPath(item.url) == targetPath);
    await prefs.setString(_keyHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }
}

// --- 网络请求/数据抓取 ---
class AnimeApiService {
  // 修改：去掉 const，改为静态变量，默认值保留一个可用的
  static String baseUrl = 'https://omofun03.top';
  // 发布页地址
  static const String publishPageUrl = 'https://omofun111.top/';

  // 统一的请求头管理
  static Map<String, String> _getHeaders({String? referer}) {
    return {
      'User-Agent': 'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 CrKey/1.54.248666 Edg/143.0.0.0',
      'Referer': referer ?? baseUrl,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };
  }

  // 1. 获取周更表
  static Future<List<WeeklyData>> fetchAnimeData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        var document = parse(response.body);
        var modules = document.querySelectorAll('.module');
        var targetModule = modules.firstWhere(
              (m) => m.querySelector('.module-title')?.text.contains("一月新番") ?? false,
          orElse: () => modules.first,
        );

        var tabs = targetModule.querySelectorAll('.module-tab-item');
        var lists = targetModule.querySelectorAll('.module-main.tab-list');

        List<WeeklyData> tempList = [];
        for (int i = 0; i < tabs.length; i++) {
          String day = tabs[i].attributes['data-dropdown-value'] ?? "";
          List<AnimeItem> items = [];
          var animeNodes = lists[i].querySelectorAll('.module-item');

          for (var node in animeNodes) {
            var img = node.querySelector('img');
            String relativeUrl = node.attributes['href'] ?? "";
            String fullUrl = relativeUrl.startsWith('http') ? relativeUrl : "$baseUrl$relativeUrl";

            items.add(AnimeItem(
              title: node.attributes['title'] ?? "",
              imageUrl: img?.attributes['data-original'] ?? img?.attributes['src'] ?? "",
              note: node.querySelector('.module-item-note')?.text ?? "",
              url: fullUrl,
            ));
          }
          tempList.add(WeeklyData(day: day, items: items));
        }
        return tempList;
      } else {
        throw Exception("请求失败：状态码 ${response.statusCode}");
      }
    } catch (e) {
      print("数据抓取失败: $e");
      rethrow;
    }
  }

  // 2. 获取动画详情
  static Future<AnimeDetail> fetchAnimeDetail(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _getHeaders(referer: baseUrl),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);
        String title = document.querySelector('.module-info-heading h1')?.text ?? "未知";

        String imageUrl = "";
        var picElement = document.querySelector('.module-item-pic img');
        if (picElement != null) {
          imageUrl = picElement.attributes['data-original'] ?? picElement.attributes['src'] ?? "";
        } else {
          imageUrl = document.querySelector('.module-info-poster img')?.attributes['data-original'] ?? "";
        }

        String intro = document.querySelector('.module-info-introduction-content')?.text.trim() ?? "";
        String updateTime = "";
        var items = document.querySelectorAll('.module-info-item');
        for (var item in items) {
          if (item.text.contains("更新：")) {
            updateTime = item.querySelector('.module-info-item-content')?.text ?? "";
          }
        }
        var sourceNodes = document.querySelectorAll('.module-tab-item.tab-item');
        List<String> sourceNames = sourceNodes.map((e) => e.querySelector('span')?.text ?? "").toList();
        var listContainers = document.querySelectorAll('.module-list.tab-list');
        List<PlaySource> playSources = [];
        for (int i = 0; i < sourceNames.length; i++) {
          List<Episode> episodes = [];
          if (i < listContainers.length) {
            var links = listContainers[i].querySelectorAll('.module-play-list-link');
            for (var link in links) {
              String relativeEpisodeUrl = link.attributes['href'] ?? "";
              String fullEpisodeUrl = relativeEpisodeUrl.startsWith('http') ? relativeEpisodeUrl : "$baseUrl$relativeEpisodeUrl";
              episodes.add(Episode(
                name: link.querySelector('span')?.text ?? "",
                url: fullEpisodeUrl,
              ));
            }
          }
          playSources.add(PlaySource(sourceName: sourceNames[i], episodes: episodes));
        }
        return AnimeDetail(
          title: title,
          imageUrl: imageUrl,
          introduction: intro,
          updateTime: updateTime,
          playSources: playSources,
        );
      } else {
        throw Exception("详情页请求失败");
      }
    } catch (e) {
      print("抓取详情异常: $e");
      rethrow;
    }
  }

  // 3. 获取视频真实播放地址
  static Future<String> getRealVideoUrl(String playPageUrl) async {
    try {
      print("正在请求视频页面: $playPageUrl");

      final response = await http.get(
        Uri.parse(playPageUrl),
        headers: _getHeaders(referer: playPageUrl),
      );

      if (response.statusCode != 200) {
        print("请求失败，状态码: ${response.statusCode}");
        return "";
      }

      String html = response.body;
      RegExp regExp = RegExp(
        r'var\s+player_aaaa\s*=\s*(\{.*?\});',
        dotAll: true,
      );

      Match? match = regExp.firstMatch(html);

      if (match != null) {
        String jsonStr = match.group(1)!;
        try {
          Map<String, dynamic> data = jsonDecode(jsonStr);
          String videoUrl = data['url'] ?? "";

          if (videoUrl.isNotEmpty) {
            videoUrl = videoUrl.replaceAll(r'\/', '/');
            print("提取成功: $videoUrl");
            return videoUrl;
          }
        } catch (e) {
          RegExp urlReg = RegExp(r'"url"\s*:\s*"([^"]+)"');
          Match? urlMatch = urlReg.firstMatch(jsonStr);
          if (urlMatch != null) {
            return urlMatch.group(1)!.replaceAll(r'\/', '/');
          }
        }
      } else {
        print("未在页面中找到 player_aaaa 对象");
      }
    } catch (e) {
      print("提取过程发生异常: $e");
    }
    return "";
  }

  // 4. 搜索功能
  static Future<SearchResult> searchAnime(String keyword, {int page = 1}) async {
    try {
      // 构造URL
      // 第一页通常使用查询参数: /vod/search.html?wd=xxx
      // 后续分页通常使用路径参数: /vod/search/page/2/wd/xxx.html
      // 为了统一和简单，我们尽量适配服务端的分页逻辑

      String requestUrl;
      if (page == 1) {
        requestUrl = '$baseUrl/vod/search.html?wd=$keyword';
      } else {
        // 注意：URL中的中文需要编码，但通常服务端路径中的编码可能各有不同
        // 这里使用Uri.encodeComponent进行编码
        requestUrl = '$baseUrl/vod/search/page/$page/wd/$keyword.html';
      }
      print("正在搜索: $requestUrl");
      final response = await http.get(
        Uri.parse(requestUrl),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);

        // 解析列表
        var items = <AnimeItem>[];
        var moduleItems = document.querySelectorAll('.module-card-item'); // 根据提供的HTML，搜索结果使用这个类名
        for (var node in moduleItems) {
          // 获取图片
          var imgTag = node.querySelector('.module-item-pic img');
          String imageUrl = imgTag?.attributes['data-original'] ?? imgTag?.attributes['src'] ?? "";

          // 获取链接
          var linkTag = node.querySelector('.module-card-item-poster'); // 或者是 .module-card-item-title > a
          String href = linkTag?.attributes['href'] ?? "";
          String fullUrl = href.startsWith('http') ? href : "$baseUrl$href";

          // 获取标题
          var titleTag = node.querySelector('.module-card-item-title a strong') ?? node.querySelector('.module-card-item-title a');
          String title = titleTag?.text.trim() ?? "";

          // 获取状态/备注
          String note = node.querySelector('.module-item-note')?.text ?? "";
          items.add(AnimeItem(
              title: title,
              imageUrl: imageUrl,
              note: note,
              url: fullUrl
          ));
        }
        // 判断是否有下一页
        // 逻辑：检查分页栏中是否有 text 为 "下一页" 的链接，且 href 不为 javascript:;
        bool hasNext = false;
        var pageLinks = document.querySelectorAll('.page-link');
        for (var link in pageLinks) {
          if (link.text.contains("下一页") || link.attributes['title'] == '下一页') {
            String nextHref = link.attributes['href'] ?? "";
            // 简单的判断，如果下一页的链接包含具体路径，则认为有下一页
            if (nextHref.contains("/page/")) {
              hasNext = true;
            }
            break;
          }
        }
        return SearchResult(items: items, hasNextPage: hasNext);
      } else {
        throw Exception("搜索请求失败: ${response.statusCode}");
      }
    } catch (e) {
      print("搜索异常: $e");
      // 发生错误返回空列表
      return SearchResult(items: [], hasNextPage: false);
    }
  }

  // [新增] 5. 通过ID获取视频信息 (用于ID搜索)
  static Future<AnimeItem?> getAnimeById(String id) async {
    // 构造完整的详情页 URL
    String url = '$baseUrl/vod/detail/id/$id.html';
    try {
      // 复用已有的 fetchAnimeDetail 方法来获取标题、图片等信息
      AnimeDetail detail = await fetchAnimeDetail(url);

      // 将详情转换为列表项对象，以便在视频卡片中显示
      return AnimeItem(
        title: detail.title,
        imageUrl: detail.imageUrl,
        note: "ID直达", // 给个特殊备注
        url: url,
      );
    } catch (e) {
      print("ID搜索失败: $e");
      return null;
    }
  }

  // [新增] 6. 获取分类库数据 (动画库/电影库等)
  static Future<SearchResult> fetchCategoryData(int typeId, {int page = 1}) async {
    try {
      // 构造URL
      // 第1页: https://omofun03.top/vod/show/id/3.html
      // 第2页: https://omofun03.top/vod/show/id/3/page/2.html
      String requestUrl;
      if (page == 1) {
        requestUrl = '$baseUrl/vod/show/id/$typeId.html';
      } else {
        requestUrl = '$baseUrl/vod/show/id/$typeId/page/$page.html';
      }
      print("正在请求分类库: $requestUrl");
      final response = await http.get(
        Uri.parse(requestUrl),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        var document = parse(response.body);
        var items = <AnimeItem>[];
        // 解析列表项
        // 根据你提供的HTML，类名是 module-poster-item module-item
        var itemNodes = document.querySelectorAll('.module-item');
        for (var node in itemNodes) {
          // 跳过没有图片的节点（防止选中tab标题等无关元素）
          var imgTag = node.querySelector('.module-item-pic img');
          if (imgTag == null) continue;
          String imageUrl = imgTag.attributes['data-original'] ?? imgTag.attributes['src'] ?? "";
          String title = node.attributes['title'] ?? node.querySelector('.module-poster-item-title')?.text ?? "";
          String note = node.querySelector('.module-item-note')?.text ?? "";
          String href = node.attributes['href'] ?? "";
          String fullUrl = href.startsWith('http') ? href : "$baseUrl$href";
          items.add(AnimeItem(
            title: title,
            imageUrl: imageUrl,
            note: note,
            url: fullUrl,
          ));
        }
        // 解析分页
        bool hasNext = false;
        var pageContainer = document.querySelector('#page');
        if (pageContainer != null) {
          var nextLink = pageContainer.querySelector('.page-next');
          // 如果存在下一页的链接，并且href不为空且不是javascript:;
          if (nextLink != null && (nextLink.attributes['href']?.contains('/page/') ?? false)) {
            hasNext = true;
          }
        }
        return SearchResult(items: items, hasNextPage: hasNext);
      } else {
        throw Exception("分类库请求失败: ${response.statusCode}");
      }
    } catch (e) {
      print("分类库获取异常: $e");
      return SearchResult(items: [], hasNextPage: false);
    }
  }

  // 新增：初始化 BaseUrl (在 main.dart 中调用)
  static Future<void> init() async {
    String? savedUrl = await AnimeStorageService.getBaseUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      // 简单的格式校验，确保没有结尾的 /
      if (savedUrl.endsWith('/')) {
        savedUrl = savedUrl.substring(0, savedUrl.length - 1);
      }
      baseUrl = savedUrl;
      print("已加载本地配置 BaseUrl: $baseUrl");
    }
  }

  // 新增：获取最新可用线路列表
  static Future<List<RouteItem>> fetchAvailableRoutes() async {
    try {
      print("正在获取线路列表: $publishPageUrl");
      final response = await http.get(Uri.parse(publishPageUrl));

      if (response.statusCode == 200) {
        // ========== 关键修复：手动用UTF-8解码响应内容 ==========
        // 避免默认解码方式导致的中文乱码
        String htmlContent = utf8.decode(response.bodyBytes);
        var document = parse(htmlContent);
        // ======================================================

        var urlList = document.querySelector('#url-list');
        if (urlList == null) return [];
        List<RouteItem> routes = [];
        var listItems = urlList.querySelectorAll('li');
        for (var li in listItems) {
          // 解析结构: <div class="url-content"> -> <span>名字</span> -> <a href="url">
          var contentDiv = li.querySelector('.url-content');
          if (contentDiv != null) {
            String name = contentDiv.querySelector('span')?.text.trim() ?? "未知线路";
            String url = contentDiv.querySelector('a')?.attributes['href']?.trim() ?? "";

            // 简单的过滤，必须是http开头
            if (url.startsWith('http')) {
              // 去除末尾斜杠，统一格式
              if (url.endsWith('/')) {
                url = url.substring(0, url.length - 1);
              }
              routes.add(RouteItem(name: name, url: url));
            }
          }
        }

        // ========== 新增的打印逻辑 ==========
        // 1. 打印获取到的线路总数
        print("成功获取线路列表，共 ${routes.length} 条数据");
        // 2. 遍历打印每条线路的详细信息
        // if (routes.isNotEmpty) {
        //   print("线路详情：");
        //   for (int i = 0; i < routes.length; i++) {
        //     print("${i+1}. ${routes[i].name}:${routes[i].url}");
        //   }
        // }
        // ====================================

        return routes;
      }
    } catch (e) {
      print("获取线路失败: $e");
    }
    return [];
  }
}