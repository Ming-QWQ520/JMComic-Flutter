import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../services/github_service.dart';
import '../../services/storage_service.dart';
import '../../services/update_service.dart';

/// 新版本提示弹窗（需求：每次进入 APP 检测更新，有新版则弹窗提示）。
///
/// - 展示新版本号与更新内容（滚动区）；
/// - 两条下载通道可选：「直链下载」（GitHub 直链）与
///   「gh-proxy 加速」（前缀加速，失败自动回退直链）；
/// - Android 内下载 APK 并拉起安装器；桌面端一键打开 Release 页；
/// - 下载中展示进度与百分比，完成后提示安装确认。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final ReleaseInfo info;

  /// 便捷弹出。
  static Future<void> show(BuildContext context, ReleaseInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String _status = '';

  bool get _isAndroid => Platform.isAndroid;

  /// 按指定通道下载并拉起安装。
  Future<void> _download({required bool useProxy}) async {
    if (_downloading) return;
    // 桌面端：直接打开 Release 页由用户手动下载。
    if (!_isAndroid) {
      await StorageService.openUrl(widget.info.htmlUrl);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = '';
    });
    try {
      final file = await UpdateService.downloadApk(
        release: widget.info,
        useProxy: useProxy,
        onProgress: (double p) {
          if (mounted) setState(() => _progress = p);
        },
        onStatus: (String s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _downloading = false;
          _status = '下载失败，请检查网络后重试';
        });
        return;
      }
      setState(() => _status = '下载完成，正在拉起安装…');
      final ok = await UpdateService.installApk(file);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = ok
            ? '已拉起系统安装器，请确认安装'
            : '无法拉起安装器，请允许"安装未知应用"后重试';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _status = '下载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = widget.info;
    final body = info.body.trim();

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.rocket_launch_rounded,
                size: 22, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '发现新版本 v${info.version}',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.primary,
                  ),
                ),
                Text(
                  '当前版本 v$kAppVersion',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (body.isNotEmpty) ...<Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(
                    body,
                    style: tt.bodySmall?.copyWith(
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _status,
                  style: tt.labelSmall?.copyWith(
                    color: _status.contains('失败')
                        ? cs.error
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            if (_downloading) ...<Widget>[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _progress > 0
                      ? '${(_progress * 100).toStringAsFixed(1)}%'
                      : '连接中…',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        // —— 两条下载通道（需求：弹窗可选 直链 / gh-proxy）——
        if (_isAndroid)
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: _downloading ? null : () => _download(useProxy: false),
                  icon: _downloading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.link_rounded, size: 16),
                  label: const Text('直链下载'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _downloading ? null : () => _download(useProxy: true),
                  icon: const Icon(Icons.speed_rounded, size: 16),
                  label: const Text('加速下载'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _download(useProxy: true),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('前往 Release 页下载'),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _downloading ? null : () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
        ),
      ],
    );
  }
}
