import 'package:flutter/material.dart';

import '../../../core/category/category_filter_service.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_tokens.dart';

class CategoryFilterKeywordsDialog extends StatefulWidget {
  final CategoryFilterService service;

  const CategoryFilterKeywordsDialog({
    super.key,
    required this.service,
  });

  @override
  State<CategoryFilterKeywordsDialog> createState() =>
      _CategoryFilterKeywordsDialogState();
}

class _CategoryFilterKeywordsDialogState
    extends State<CategoryFilterKeywordsDialog> {
  late final TextEditingController _inputController;
  late final List<String> _keywords;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _keywords = List.from(widget.service.activeHiddenKeywords);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (!_keywords.contains(text)) {
      setState(() {
        _keywords.add(text);
      });
    }
    _inputController.clear();
  }

  void _removeKeyword(String keyword) {
    setState(() {
      _keywords.remove(keyword);
    });
  }

  void _clearAll() {
    setState(() {
      _keywords.clear();
    });
  }

  void _resetToDefault() {
    setState(() {
      _keywords.clear();
      _keywords.addAll(CategoryFilterService.defaultHiddenNames);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Dialog(
      backgroundColor: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 640,
          maxHeight: 580,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部：标题与关闭按钮
              Row(
                children: [
                  Text(
                    '分类过滤关键字管理',
                    style: TextStyle(
                      color: palette.textTitle,
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: Icon(Icons.close_rounded, color: palette.textSub),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Text(
                '在自动模式下，CMS/JSON 站点的分类若与以下名单精确匹配（整名相等，忽略大小写与空格），'
                '将被自动隐藏。您可以任意点击标签右上角「×」单独删除、清空或重新恢复预设。Spider 站一律不过滤。',
                style: TextStyle(
                  color: palette.textSub,
                  fontSize: AppType.body,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // 添加输入行
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: TextStyle(
                        fontSize: AppType.body,
                        color: palette.textTitle,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入要精确隐藏的分类名（如：少儿、综艺）',
                        hintStyle: TextStyle(
                          fontSize: AppType.body,
                          color: palette.textDim,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: palette.raised,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          borderSide: BorderSide(color: palette.accent),
                        ),
                      ),
                      onSubmitted: (_) => _addKeyword(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addKeyword,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 过滤关键字列表区域标题与清空按钮
              Row(
                children: [
                  Text(
                    '生效中的过滤名单 (${_keywords.length} 个)',
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.bold,
                      color: palette.textTitle,
                    ),
                  ),
                  const Spacer(),
                  if (_keywords.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: Icon(
                        Icons.delete_sweep_rounded,
                        size: 16,
                        color: palette.warning,
                      ),
                      label: Text(
                        '清空全部',
                        style: TextStyle(
                          color: palette.warning,
                          fontSize: AppType.caption,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // 关键字 Chips 区域
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: palette.border),
                  ),
                  child: _keywords.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.filter_list_off_rounded,
                                size: 36,
                                color: palette.textDim,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '暂无过滤关键字（所有分类均正常显示）',
                                style: TextStyle(
                                  fontSize: AppType.body,
                                  color: palette.textDim,
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: _resetToDefault,
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                ),
                                label: const Text('恢复系统预设 (35 个)'),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _keywords.map((k) {
                              return Chip(
                                label: Text(k),
                                labelStyle: TextStyle(
                                  fontSize: AppType.caption,
                                  color: palette.textTitle,
                                ),
                                backgroundColor: palette.card,
                                deleteIcon: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: palette.textSub,
                                ),
                                onDeleted: () => _removeKeyword(k),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),

              // 底部操作栏
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('恢复系统默认 (35 个)'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.warning,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      '取消',
                      style: TextStyle(color: palette.textSub),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await widget.service.setHiddenKeywords(_keywords);
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
