import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/errors/api_failure.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/attachments.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/widgets.dart';

typedef AttachmentPicker =
    Future<List<SelectedAttachment>?> Function(bool avatar);
typedef AttachmentSaver =
    Future<String?> Function(String name, Uint8List bytes);
final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => (avatar) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: !avatar,
      withData: true,
      type: avatar ? FileType.custom : FileType.any,
      allowedExtensions: avatar ? ['png', 'jpg', 'jpeg', 'webp'] : null,
    );
    if (result == null) return null;
    final files = <SelectedAttachment>[];
    for (final file in result.files) {
      if (file.size < 1 ||
          file.size > maximumAttachmentBytes ||
          file.bytes == null) {
        throw const ApiFailure(
          FailureKind.validation,
          '文件大小须为1字节至10MB，且能够读取文件内容',
        );
      }
      final selected = SelectedAttachment(file.name, file.bytes!);
      selected.validate(avatar: avatar);
      files.add(selected);
    }
    return files;
  },
);
final attachmentSaverProvider = Provider<AttachmentSaver>(
  (ref) =>
      (name, bytes) => FilePicker.platform.saveFile(
        dialogTitle: '保存附件',
        fileName: safeAttachmentName(name),
        bytes: bytes,
      ),
);

class AttachmentSelection {
  const AttachmentSelection(this.files, {required this.ready});
  final List<UploadedAttachment> files;
  final bool ready;
}

class _UploadEntry {
  _UploadEntry(this.file);
  final SelectedAttachment file;
  UploadedAttachment? uploaded;
  Object? error;
  bool sending = false;
  double? progress;
  CancelToken? cancellation;
}

/// Owns local bytes and cancellation; parent receives only successful server metadata.
class AttachmentEditor extends ConsumerStatefulWidget {
  const AttachmentEditor({
    super.key,
    required this.onChanged,
    this.avatar = false,
    this.enabled = true,
  });
  final ValueChanged<AttachmentSelection> onChanged;
  final bool avatar, enabled;
  @override
  ConsumerState<AttachmentEditor> createState() => _AttachmentEditorState();
}

class _AttachmentEditorState extends ConsumerState<AttachmentEditor> {
  final entries = <_UploadEntry>[];
  String? error;
  bool picking = false;
  bool denied = false;
  late final String account = ref.read(sessionProvider).id;
  bool get authorized =>
      mounted &&
      account == ref.read(sessionProvider).id &&
      ref.read(sessionProvider).canReadBusiness;
  void changed() => widget.onChanged(
    AttachmentSelection(
      [
        for (final e in entries)
          if (e.uploaded != null) e.uploaded!,
      ],
      ready:
          !denied &&
          !picking &&
          entries.every((e) => e.uploaded != null && !e.sending),
    ),
  );
  Future<void> choose() async {
    setState(() {
      picking = true;
      error = null;
    });
    changed();
    try {
      final files = await ref.read(attachmentPickerProvider)(widget.avatar);
      if (!authorized || files == null || files.isEmpty) return;
      for (final file in files) {
        file.validate(avatar: widget.avatar);
      }
      if (widget.avatar) {
        for (final e in entries) {
          e.cancellation?.cancel();
        }
        entries.clear();
      }
      final newEntries = [for (final file in files) _UploadEntry(file)];
      setState(() => entries.addAll(newEntries));
      for (final e in newEntries) {
        if (!authorized) break;
        await upload(e);
      }
    } catch (e) {
      if (authorized) setState(() => error = '$e');
    } finally {
      if (authorized) {
        setState(() => picking = false);
        changed();
      }
    }
  }

  Future<void> upload(_UploadEntry entry) async {
    if (!authorized || !entries.contains(entry)) return;
    final repository = ref.read(repositoryProvider);
    final token = CancelToken();
    setState(() {
      entry.error = null;
      entry.sending = true;
      entry.cancellation = token;
    });
    changed();
    try {
      final result = await repository.uploadAttachment(
        entry.file,
        cancelToken: token,
        onProgress: (sent, total) {
          if (authorized && !token.isCancelled && entries.contains(entry)) {
            setState(() => entry.progress = total > 0 ? sent / total : null);
          }
        },
      );
      if (authorized && !token.isCancelled && entries.contains(entry)) {
        setState(() => entry.uploaded = result);
      }
    } catch (e) {
      if (authorized && !token.isCancelled && entries.contains(entry)) {
        setState(() => entry.error = e);
        if (e is ApiFailure &&
            [
              FailureKind.forbidden,
              FailureKind.unauthorized,
            ].contains(e.kind)) {
          for (final other in entries) {
            other.cancellation?.cancel();
          }
          setState(() {
            entries.clear();
            denied = true;
            error = '上传权限已失效，请返回后重新确认权限';
          });
        }
      }
    } finally {
      if (authorized) {
        setState(() => entry.sending = false);
        changed();
      }
    }
  }

  void remove(_UploadEntry e) {
    e.cancellation?.cancel();
    setState(() => entries.remove(e));
    changed();
  }

  @override
  void dispose() {
    for (final e in entries) {
      e.cancellation?.cancel();
    }
    entries.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, next) {
      if (next.id != account || !next.canReadBusiness) {
        for (final e in entries) {
          e.cancellation?.cancel();
        }
        setState(() {
          entries.clear();
          denied = true;
          error = '账号状态已变化，请重新进入编辑';
        });
        changed();
      }
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: !widget.enabled || picking || !authorized || denied
              ? null
              : choose,
          icon: const Icon(Icons.attach_file),
          label: Text(
            picking
                ? '正在上传…'
                : widget.avatar
                ? '选择并上传新头像'
                : '选择并上传附件',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.avatar
              ? 'PNG、JPEG或WebP，最大10MB。保存资料后更换头像。'
              : '每个文件最大10MB。上传完成后随任务提交；移除不提交该文件。',
        ),
        for (final e in entries)
          PaperSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  e.uploaded?.name ?? safeAttachmentName(e.file.name),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${(e.file.bytes.length / 1024).toStringAsFixed(1)} KB · ${e.uploaded != null
                      ? '已上传，等待表单提交'
                      : e.sending
                      ? '上传中'
                      : '上传未完成'}',
                ),
                if (e.sending) LinearProgressIndicator(value: e.progress),
                if (e.error != null)
                  Text(
                    '上传失败：${e.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Wrap(
                  children: [
                    if (e.error != null)
                      TextButton(
                        onPressed: widget.enabled && !e.sending
                            ? () => upload(e)
                            : null,
                        child: const Text('重试上传'),
                      ),
                    TextButton(
                      onPressed: widget.enabled ? () => remove(e) : null,
                      child: Text(e.sending ? '取消上传并移除' : '移除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

final protectedAvatarProvider = FutureProvider.autoDispose
    .family<DownloadedAttachment, String>((ref, id) async {
      final repository = ref.watch(repositoryProvider), token = CancelToken();
      ref.onDispose(() => token.cancel());
      final file = await repository.downloadAttachment(id, cancelToken: token);
      if (!isAvatarImage(file.bytes)) {
        throw const ApiFailure(FailureKind.validation, '头像不是支持的图片');
      }
      return file;
    });

class ProtectedAvatar extends ConsumerWidget {
  const ProtectedAvatar({
    super.key,
    required this.name,
    this.attachmentId,
    this.radius = 28,
  });
  final String name;
  final String? attachmentId;
  final double radius;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget fallback() => CircleAvatar(
      radius: radius,
      child: Text(name.isEmpty ? '我' : name.substring(0, 1)),
    );
    if (attachmentId == null ||
        attachmentId!.isEmpty ||
        !ref.watch(sessionProvider).canReadBusiness) {
      return fallback();
    }
    return ref
        .watch(protectedAvatarProvider(attachmentId!))
        .when(
          loading: () => SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: const Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => Semantics(
            label: '头像未能加载，点击重试',
            button: true,
            child: InkWell(
              onTap: () =>
                  ref.invalidate(protectedAvatarProvider(attachmentId!)),
              child: fallback(),
            ),
          ),
          data: (file) => ClipOval(
            child: Image.memory(
              file.bytes,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              semanticLabel: '$name的头像',
              errorBuilder: (_, _, _) => fallback(),
            ),
          ),
        );
  }
}

class AttachmentDownloadPage extends ConsumerStatefulWidget {
  const AttachmentDownloadPage(this.id, {super.key});
  final String id;
  @override
  ConsumerState<AttachmentDownloadPage> createState() =>
      _AttachmentDownloadPageState();
}

class _AttachmentDownloadPageState
    extends ConsumerState<AttachmentDownloadPage> {
  bool busy = false, forbidden = false;
  String? result;
  CancelToken? cancellation;
  Future<void> save() async {
    final account = ref.read(sessionProvider).id, token = CancelToken();
    final saver = ref.read(attachmentSaverProvider),
        repository = ref.read(repositoryProvider);
    cancellation = token;
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final file = await repository.downloadAttachment(
        widget.id,
        cancelToken: token,
      );
      if (!mounted ||
          token.isCancelled ||
          account != ref.read(sessionProvider).id ||
          !ref.read(sessionProvider).canReadBusiness) {
        return;
      }
      final path = await saver(file.name, file.bytes);
      if (mounted &&
          account == ref.read(sessionProvider).id &&
          !token.isCancelled) {
        setState(() => result = path == null ? '已取消保存，文件未写入' : '附件已保存：$path');
      }
    } catch (e) {
      if (mounted &&
          account == ref.read(sessionProvider).id &&
          !token.isCancelled) {
        setState(() {
          forbidden =
              e is ApiFailure &&
              [
                FailureKind.forbidden,
                FailureKind.unauthorized,
              ].contains(e.kind);
          result = '下载未完成：$e';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, _) {
      cancellation?.cancel();
      if (mounted) {
        setState(() {
          result = null;
          forbidden = true;
        });
      }
    });
    return PageFrame(
      title: '任务附件',
      bottom: BottomActions(
        primary: SunnyPrimaryButton.icon(
          loading: busy,
          onPressed:
              busy || forbidden || !ref.watch(sessionProvider).canReadBusiness
              ? null
              : save,
          icon: const Icon(Icons.download_outlined),
          label: const Text('下载并保存附件'),
        ),
      ),
      child: PageBody(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 56),
          const SizedBox(height: 20),
          const Text('下载时重新检查访问权限。选择保存位置后保留完整文件，取消保存不会创建文件。'),
          const SizedBox(height: 20),
          if (result != null) Text(result!),
          if (forbidden) const Text('权限已失效，请返回任务重新确认访问范围。'),
          const DemoLabel(),
        ],
      ),
    );
  }
}
