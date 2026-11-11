import 'package:pandora_mobile/shared/curated_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
import 'package:pandora_mobile/data/models/tenure.dart';
import 'package:pandora_mobile/shared/attachment_widgets.dart';
import 'package:pandora_mobile/shared/widgets.dart';
import 'package:pandora_mobile/shared/paper_layout.dart';
import 'package:pandora_mobile/shared/generated_assets.dart';
import 'package:pandora_mobile/theme/app_theme.dart';

class OwnProfilePage extends ConsumerStatefulWidget {
  const OwnProfilePage({super.key});

  @override
  ConsumerState<OwnProfilePage> createState() => _OwnProfilePageState();
}

class _OwnProfilePageState extends ConsumerState<OwnProfilePage> {
  final introduction = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final gender = TextEditingController();
  final age = TextEditingController();
  bool editing = false, saving = false;
  String? error;
  late String accountId = ref.read(sessionProvider).id;

  @override
  void dispose() {
    introduction.dispose();
    phone.dispose();
    email.dispose();
    gender.dispose();
    age.dispose();
    super.dispose();
  }

  void beginEdit(Record profile) {
    introduction.text =
        '${profile.fields['个人介绍'] ?? profile.fields['body'] ?? ''}';
    phone.text = '${profile.fields['phone'] ?? profile.fields['手机号'] ?? ''}';
    email.text = '${profile.fields['email'] ?? profile.fields['邮箱'] ?? ''}';
    gender.text = '${profile.fields['gender'] ?? profile.fields['性别'] ?? ''}';
    age.text = '${profile.fields['age'] ?? profile.fields['年龄'] ?? ''}';
    setState(() {
      editing = true;
      error = null;
    });
  }

  void cancelEdit() {
    setState(() {
      editing = false;
      error = null;
    });
  }

  Future<void> saveProfile(
    Record profile,
    String avatarId, {
    bool includeProfileEdits = true,
  }) async {
    final saveFields = editing && includeProfileEdits;
    final current = ref.read(sessionProvider);
    if (current.id != accountId || !current.canReadBusiness) {
      setState(() => error = '账号状态已变化，请重新进入资料页');
      return;
    }
    if (saveFields) {
      final phoneValue = phone.text.trim();
      if (phoneValue.isNotEmpty &&
          !RegExp(r'^\+?[0-9][0-9 ()-]{4,18}[0-9]$').hasMatch(phoneValue)) {
        setState(() => error = '请输入有效电话号码');
        return;
      }
      final emailValue = email.text.trim();
      if (emailValue.isNotEmpty &&
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(emailValue)) {
        setState(() => error = '请输入有效邮箱地址');
        return;
      }
      if (age.text.trim().isNotEmpty &&
          (int.tryParse(age.text.trim()) ?? -1) < 0) {
        setState(() => error = '年龄必须为非负整数');
        return;
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final introductionValue = saveFields
          ? introduction.text.trim()
          : '${profile.fields['个人介绍'] ?? profile.fields['body'] ?? ''}';
      await ref
          .read(repositoryProvider)
          .execute(
            'organization/profile',
            Command(
              'update',
              {
                'id': accountId,
                '个人介绍': introductionValue,
                if (saveFields) ...{
                  '手机号': phone.text.trim(),
                  '邮箱': email.text.trim(),
                  '性别': gender.text.trim(),
                  '年龄': age.text.trim().isEmpty
                      ? null
                      : int.parse(age.text.trim()),
                },
                'avatarAttachmentId': avatarId,
              },
              version: profile.version,
              idempotencyKey: 'profile:$accountId:${profile.version}:update',
            ),
          );
      if (!mounted || ref.read(sessionProvider).id != accountId) return;
      ref.invalidate(itemProvider(('organization/profile', accountId)));
      refreshBusiness(ref);
      setState(() {
        if (saveFields) editing = false;
        saving = false;
      });
    } catch (failure) {
      if (mounted && ref.read(sessionProvider).id == accountId) {
        setState(() {
          saving = false;
          error = '$failure';
        });
      }
    }
  }

  Future<void> showAvatarDetails(Record profile, String name) async {
    var selecting = false;
    var uploading = const AttachmentSelection([], ready: true);
    var avatarError = '';
    var avatarSaving = false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭头像详情',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .72),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : WorkMotion.overlay,
      pageBuilder: (dialogContext, _, _) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Center(
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .78,
              ),
              child: PaperSurface(
                color: Theme.of(context).colorScheme.surface,
                borderColor: Theme.of(context).colorScheme.outlineVariant,
                padding: const EdgeInsets.all(20),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProtectedAvatar(
                              name: name,
                              attachmentId:
                                  uploading.files.firstOrNull?.id ??
                                  profile.fields['avatarAttachmentId']
                                      as String?,
                              radius: 76,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (selecting) ...[
                              const SizedBox(height: 16),
                              AttachmentEditor(
                                key: ValueKey('profile-avatar:$accountId'),
                                avatar: true,
                                enabled: !avatarSaving,
                                onChanged: (selection) => setDialogState(() {
                                  uploading = selection;
                                }),
                              ),
                              if (avatarError.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    avatarError,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: avatarSaving
                                          ? null
                                          : () => Navigator.pop(dialogContext),
                                      child: const Text('取消'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed:
                                          avatarSaving ||
                                              !uploading.ready ||
                                              uploading.files.isEmpty
                                          ? null
                                          : () async {
                                              setDialogState(() {
                                                avatarSaving = true;
                                                avatarError = '';
                                              });
                                              try {
                                                await saveProfile(
                                                  profile,
                                                  uploading.files.first.id,
                                                  includeProfileEdits: false,
                                                );
                                                if (mounted &&
                                                    dialogContext.mounted &&
                                                    error == null) {
                                                  Navigator.pop(dialogContext);
                                                } else if (dialogContext
                                                    .mounted) {
                                                  setDialogState(() {
                                                    avatarSaving = false;
                                                    avatarError =
                                                        error ?? '资料未保存，请重试';
                                                  });
                                                }
                                              } catch (failure) {
                                                if (dialogContext.mounted) {
                                                  setDialogState(() {
                                                    avatarSaving = false;
                                                    avatarError = '$failure';
                                                  });
                                                }
                                              }
                                            },
                                      child: Text(
                                        avatarSaving ? '保存中…' : '保存头像',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (!selecting)
                      Positioned(
                        top: 0,
                        left: 0,
                        child: IconButton(
                          tooltip: '更换头像',
                          onPressed: () => setDialogState(() {
                            selecting = true;
                            avatarError = '';
                          }),
                          icon: Image.asset(
                            'assets/generated_ui/sunshine/icons/edit.png',
                            width: 26,
                            height: 26,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: '关闭',
                        onPressed: avatarSaving
                            ? null
                            : () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .96, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _profileOverview(BuildContext context, Record value, Session user) {
    final department = value.fields['departmentName'] ?? value.fields['部门'];
    final position = value.fields['position'] ?? value.fields['职位'];
    final intro = '${value.fields['个人介绍'] ?? value.fields['body'] ?? ''}'
        .trim();
    final entries =
        <(String, String, dynamic, TextEditingController?, TextInputType?)>[
          (
            '电话',
            'phone',
            value.fields['phone'] ?? value.fields['手机号'],
            phone,
            TextInputType.phone,
          ),
          (
            '邮箱',
            'email',
            value.fields['email'] ?? value.fields['邮箱'],
            email,
            TextInputType.emailAddress,
          ),
          (
            '性别',
            'person',
            value.fields['gender'] ?? value.fields['性别'],
            gender,
            null,
          ),
          (
            '年龄',
            'birthday',
            value.fields['age'] ?? value.fields['年龄'],
            age,
            TextInputType.number,
          ),
          (
            '入职日期',
            'employment',
            employmentDateLabel(value.fields['employmentStartDate']),
            null,
            null,
          ),
          (
            '工龄',
            'tenure',
            tenureLabel(
              parseEmploymentDate(value.fields['employmentStartDate']),
              shanghaiWallTime(DateTime.now()),
            ),
            null,
            null,
          ),
        ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperSurface(
          color: SunnyPalette.primaryContainer,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: '查看${user.name}的头像详情',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: saving
                      ? null
                      : () => showAvatarDetails(value, user.name),
                  child: ProtectedAvatar(
                    name: user.name,
                    attachmentId: value.fields['avatarAttachmentId'] as String?,
                    radius: 32,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [department, position]
                          .where((v) => v != null && '$v'.trim().isNotEmpty)
                          .join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    AppLabelBadge(
                      user.role.label,
                      color: SunnyPalette.surface,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PaperSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('个人介绍', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (editing)
                TextField(
                  controller: introduction,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 500,
                  decoration: const InputDecoration(hintText: '介绍你的工作方向与经历'),
                )
              else
                Text(
                  intro.isEmpty ? '暂无个人介绍' : intro,
                  style: const TextStyle(height: 1.6),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('联系与资料', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        PaperSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/generated_ui/sunshine/icons/${entries[i].$2}.png',
                        width: 36,
                        height: 36,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              entries[i].$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 5),
                            if (editing && entries[i].$4 != null)
                              TextField(
                                controller: entries[i].$4,
                                keyboardType: entries[i].$5,
                                enabled: !saving,
                                decoration: InputDecoration(
                                  hintText: '未提供',
                                  labelText: entries[i].$1,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                ),
                              )
                            else
                              Text(
                                entries[i].$3 == null ||
                                        '${entries[i].$3}'.trim().isEmpty
                                    ? '未提供'
                                    : '${entries[i].$3}',
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < entries.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (accountId != user.id) {
      accountId = user.id;
      editing = false;
      error = null;
    }
    final profile = ref.watch(itemProvider(('organization/profile', user.id)));
    return PageFrame(
      title: '我的个人主页',
      actions: [
        if (editing)
          IconButton(
            tooltip: '取消编辑',
            onPressed: saving ? null : cancelEdit,
            icon: const Icon(Icons.close_rounded),
          )
        else
          IconButton(
            tooltip: '编辑个人资料',
            onPressed: profile.valueOrNull == null
                ? null
                : () => beginEdit(profile.valueOrNull!),
            icon: Image.asset(
              'assets/generated_ui/sunshine/icons/edit.png',
              width: 26,
              height: 26,
              excludeFromSemantics: true,
            ),
          ),
      ],
      bottom: editing
          ? BottomActions(
              primary: FilledButton.icon(
                onPressed: saving || profile.valueOrNull == null
                    ? null
                    : () => saveProfile(
                        profile.valueOrNull!,
                        '${profile.valueOrNull!.fields['avatarAttachmentId'] ?? ''}',
                      ),
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(saving ? '保存中…' : '保存'),
              ),
              secondary: OutlinedButton(
                onPressed: saving ? null : cancelEdit,
                child: const Text('取消'),
              ),
            )
          : null,
      child: PageBody(
        children: [
          profile.when(
            loading: () => const LoadingSkeleton(),
            error: (failure, _) => RecordFailure(
              failure,
              retry: () => ref.invalidate(
                itemProvider(('organization/profile', user.id)),
              ),
            ),
            data: (value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _profileOverview(context, value, user),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
