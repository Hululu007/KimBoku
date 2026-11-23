import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../api/models/vod_models.dart';
import '../api/site_api.dart';
import '../config/models/vod_config.dart';
import '../config/windows_config_storage.dart';

/// 首页分类条治理服务：
/// 1. 配置白名单优先匹配（精确同名 -> 互相包含 -> 全不匹配回退）；
/// 2. 自动模式精确名称过滤（体育/伦理/大总目录），全被隐藏时回退；
/// 3. 空分类后台并发探测（并发 3，上限 40，写入 Category_filter.json 缓存）；
/// 4. spider 站（jar/js/py/type=3）一律不过滤、不探测。
class CategoryFilterService {
  final Future<Directory> Function() _getDirectory;

  CategoryFilterService({Future<Directory> Function()? getDirectory})
      : _getDirectory = getDirectory ?? WindowsConfigStorage().getStorageDirectory;

  static const String fileName = 'Category_filter.json';

  /// 预设自动隐藏名单：精确匹配（去空白 + 小写后整名相等），不做子串匹配
  static const List<String> defaultHiddenNames = [
    // 体育类
    '足球', '篮球', '网球', '斯诺克', '台球', '羽毛球', '乒乓', '乒乓球',
    '赛车', '搏击', '拳击', '电竞', '棋牌', '体育', '运动', '赛事',
    // 伦理擦边类
    '伦理', '伦理片', '理论片', '三级', '成人', '情色', '里番', '福利',
    '擦边', '写真', '两性',
    // 大而全的总目录
    '电影', '电影片', '连续剧', '电视剧', '动漫', '动漫片', '综艺', '综艺片',
  ];

  static String normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  // 内存缓存
  bool _loaded = false;
  List<String> _hiddenKeywords = List.from(defaultHiddenNames);
  final Map<String, List<String>> _probedSites = {}; // siteKey -> emptyCategoryIds

  List<String> get activeHiddenKeywords => List.unmodifiable(_hiddenKeywords);

  // 兼容旧属性名称
  List<String> get customHiddenKeywords => activeHiddenKeywords;

  /// 1. 分类来源与顺序：配置里写了 categories（白名单）
  /// - 只显示配置里列出的分类，顺序按配置；
  /// - 匹配先精确同名，再互相包含（配置写「动漫」、接口给「国产动漫」也算），忽略空白与大小写；
  /// - 配置名一个都对不上时，退回接口原始列表（避免分类条空掉）；
  /// - 配置没写 categories 时保持接口返回顺序，不做排序。
  List<VodCategory> applyConfigCategories(
      List<String>? configCategories, List<VodCategory> rawCategories) {
    if (configCategories == null || configCategories.isEmpty) {
      return rawCategories;
    }
    if (rawCategories.isEmpty) {
      return rawCategories;
    }

    final result = <VodCategory>[];
    final matchedRawIndices = <int>{};

    for (final targetName in configCategories) {
      final targetNorm = normalize(targetName);
      if (targetNorm.isEmpty) continue;

      // 阶段 1：精确同名匹配（忽略空白与大小写）
      int foundIndex = -1;
      for (int i = 0; i < rawCategories.length; i++) {
        if (matchedRawIndices.contains(i)) continue;
        if (normalize(rawCategories[i].name) == targetNorm) {
          foundIndex = i;
          break;
        }
      }

      // 阶段 2：互相包含匹配（配置写「动漫」、接口给「国产动漫」也算；或配置写「电影片」、接口给「电影」）
      if (foundIndex == -1) {
        for (int i = 0; i < rawCategories.length; i++) {
          if (matchedRawIndices.contains(i)) continue;
          final rawNorm = normalize(rawCategories[i].name);
          if (rawNorm.contains(targetNorm) || targetNorm.contains(rawNorm)) {
            foundIndex = i;
            break;
          }
        }
      }

      if (foundIndex != -1) {
        matchedRawIndices.add(foundIndex);
        result.add(rawCategories[foundIndex]);
      }
    }

    // 配置名一个都对不上时，退回接口原始列表（避免分类条空掉）
    if (result.isEmpty) {
      return rawCategories;
    }

    return result;
  }

  /// 2. 自动模式过滤（只作用于 CMS/JSON 站）
  /// - spider 站（jar/js/py/type=3）一律不过滤：这些分类是站点自己声明的，用户明确要求别动；
  /// - 按名字隐藏：名单内的名字精确匹配（去空白 + 小写后整名相等），不做子串匹配；
  /// - 全被隐藏时退回原列表（别把分类条搞空）。
  List<VodCategory> filterAutoCategoriesForSite(
    Site site,
    List<VodCategory> categories, {
    Iterable<String>? additionalHiddenNames,
  }) {
    // spider 站一律不过滤
    if (site.usesCompanion) {
      return categories;
    }
    if (categories.isEmpty) {
      return categories;
    }

    final hiddenSet = <String>{};
    for (final name in _hiddenKeywords) {
      final n = normalize(name);
      if (n.isNotEmpty) hiddenSet.add(n);
    }
    if (additionalHiddenNames != null) {
      for (final name in additionalHiddenNames) {
        final n = normalize(name);
        if (n.isNotEmpty) hiddenSet.add(n);
      }
    }

    final filtered = categories.where((cat) {
      final catNorm = normalize(cat.name);
      // 精确匹配：名单内的名字整名相等才隐藏
      return !hiddenSet.contains(catNorm);
    }).toList();

    // 全被隐藏时退回原列表（别把分类条搞空）
    if (filtered.isEmpty) {
      return categories;
    }

    return filtered;
  }

  /// 过滤掉已探测到的空分类
  List<VodCategory> filterProbedEmptyCategories(
      Site site, List<VodCategory> categories) {
    if (site.usesCompanion) return categories;
    final emptyIds = _probedSites[site.key];
    if (emptyIds == null || emptyIds.isEmpty) return categories;

    final emptySet = emptyIds.toSet();
    final filtered =
        categories.where((cat) => !emptySet.contains(cat.id)).toList();
    return filtered.isEmpty ? categories : filtered;
  }

  /// 是否已经探测过该站源
  bool hasProbedSite(Site site) {
    if (site.usesCompanion) return true;
    return _probedSites.containsKey(site.key);
  }

  /// 读取 `Category_filter.json`
  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await _getDirectory();
      final file = File(p.join(dir.path, fileName));
      if (!await file.exists()) {
        _loaded = true;
        return;
      }
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        if (decoded['hiddenKeywords'] is List) {
          _hiddenKeywords = (decoded['hiddenKeywords'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        } else if (decoded['customHiddenKeywords'] is List) {
          // 向前兼容旧版配置
          final custom = (decoded['customHiddenKeywords'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          _hiddenKeywords = {...defaultHiddenNames, ...custom}.toList();
        }
        if (decoded['probedSites'] is Map) {
          final probed = decoded['probedSites'] as Map;
          for (final entry in probed.entries) {
            final key = entry.key.toString();
            final val = entry.value;
            if (val is Map && val['emptyCategoryIds'] is List) {
              _probedSites[key] = (val['emptyCategoryIds'] as List)
                  .map((e) => e.toString())
                  .toList();
            } else if (val is List) {
              _probedSites[key] = val.map((e) => e.toString()).toList();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CategoryFilterService] 读取 Category_filter.json 异常: $e');
    } finally {
      _loaded = true;
    }
  }

  /// 保存至 `Category_filter.json`
  Future<void> save() async {
    try {
      final dir = await _getDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final filePath = p.join(dir.path, fileName);
      final tempPath = '$filePath.tmp-${DateTime.now().microsecondsSinceEpoch}';

      final data = {
        'version': 1,
        'hiddenKeywords': _hiddenKeywords,
        'customHiddenKeywords': _hiddenKeywords, // 兼容旧版字段
        'probedSites': _probedSites.map((k, v) => MapEntry(k, {
              'emptyCategoryIds': v,
              'updatedAt': DateTime.now().toIso8601String(),
            })),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final tempFile = File(tempPath);
      await tempFile.writeAsString(jsonStr, flush: true);

      // 原子替换
      if (await File(filePath).exists()) {
        await File(filePath).delete();
      }
      await tempFile.rename(filePath);
    } catch (e) {
      debugPrint('[CategoryFilterService] 保存 Category_filter.json 异常: $e');
    }
  }

  /// 设置当前生效的全部隐藏关键字（允许用户增删、清空、恢复）
  Future<void> setHiddenKeywords(List<String> keywords) async {
    _hiddenKeywords = keywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList();
    await save();
  }

  /// 兼容旧调用名
  Future<void> setCustomHiddenKeywords(List<String> keywords) =>
      setHiddenKeywords(keywords);

  /// 重置为系统预设 35 个过滤关键字
  Future<void> resetToDefaultKeywords() async {
    _hiddenKeywords = List.from(defaultHiddenNames);
    await save();
  }

  /// 后台探测空分类：
  /// - spider 站（site.usesCompanion）一律不探测；
  /// - 已探测过的站源不再探测；
  /// - 逐个取第 1 页，list 与 filters 都为空才算空，从分类条摘掉；
  /// - 并发 3，最多 40 个，探测失败一律不当空，当前选中的分类不参与；
  /// - 结果写入 Category_filter.json。
  Future<void> probeEmptyCategoriesInBackground({
    required Site site,
    required List<VodCategory> categories,
    required VodCategory? selectedCategory,
    required SiteApi siteApi,
    required void Function(List<String> emptyCategoryIds) onEmptyDetected,
  }) async {
    // spider 站一律不探测
    if (site.usesCompanion) return;

    if (!_loaded) {
      await load();
    }

    // 已探测过的播放源下次启动不再探测, 只探测新加入的播放源
    if (_probedSites.containsKey(site.key)) {
      final cachedEmpty = _probedSites[site.key] ?? [];
      if (cachedEmpty.isNotEmpty) {
        onEmptyDetected(cachedEmpty);
      }
      return;
    }

    // 筛选候选：当前选中的分类不参与，最多 40 个
    final candidates = categories
        .where((cat) => cat.id.isNotEmpty && cat.id != selectedCategory?.id)
        .take(40)
        .toList();

    if (candidates.isEmpty) {
      _probedSites[site.key] = [];
      await save();
      return;
    }

    final newlyFoundEmptyIds = <String>[];
    const concurrency = 3;

    // 工作池实现并发 3
    int cursor = 0;
    Future<void> worker() async {
      while (true) {
        int index;
        if (cursor >= candidates.length) return;
        index = cursor++;
        final cat = candidates[index];

        try {
          final res = await siteApi.fetchCategory(
            site,
            categoryId: cat.id,
            extend: const {},
          );
          // list 与 filters 都为空才算空
          if (res.list.isEmpty && res.filters.isEmpty) {
            newlyFoundEmptyIds.add(cat.id);
          }
        } catch (_) {
          // 探测失败一律不当空
        }
      }
    }

    final workers = List.generate(
      math.min(concurrency, candidates.length),
      (_) => worker(),
    );
    await Future.wait(workers);

    _probedSites[site.key] = newlyFoundEmptyIds;
    await save();

    if (newlyFoundEmptyIds.isNotEmpty) {
      onEmptyDetected(newlyFoundEmptyIds);
    }
  }
}
