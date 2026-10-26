import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pandora_mobile/core/state/providers.dart';
import 'package:pandora_mobile/data/models/models.dart';
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
      await ref.read(repositoryProvider).execute(
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
                                      color: Theme.of(context).colorScheme.error,
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
                                      onPressed: avatarSaving ||
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
                                                } else if (dialogContext.mounted) {
                                                  setDialogState(() {
                                                    avatarSaving = false;
                                                    avatarError = error ??
                                                        '资料未保存，请重试';
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
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!selecting)
                            IconButton(
                              tooltip: '更换头像',
                              onPressed: () => setDialogState(() {
                                selecting = true;
                                avatarError = '';
                              }),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: avatarSaving
                                ? null
                                : () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
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

  Widget infoField(String label, dynamic value) => PaperSurface(
    color: DogBrandPalette.surface,
    borderColor: DogBrandPalette.line,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(color: DogBrandPalette.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value == null || '$value'.trim().isEmpty ? '未提供' : '$value',
            style: const TextStyle(fontSize: 13, color: DogBrandPalette.muted),
          ),
        ),
      ],
    ),
  );

  Widget _profileOverview(BuildContext context, Record value, Session user) {
    final department = value.fields['departmentName'] ?? value.fields['部门'];
    final position = value.fields['position'] ?? value.fields['职位'];
    final intro = '${value.fields['个人介绍'] ?? value.fields['body'] ?? ''}'.trim();
    final contact = [
      ('电话', value.fields['phone'] ?? value.fields['手机号'], Icons.phone_outlined),
      ('邮箱', value.fields['email'] ?? value.fields['邮箱'], Icons.mail_outline_rounded),
      ('性别', value.fields['gender'] ?? value.fields['性别'], Icons.wc_outlined),
      ('年龄', value.fields['age'] ?? value.fields['年龄'], Icons.cake_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperSurface(
          decorated: true,
          skin: TuantuanAssets.surfaces['warm'],
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Stack(
            children: [
              const Positioned(right: 0, top: 0, child: DogPose(index: DogAssets.sitting, size: 66)),
              Row(
                children: [
                  Semantics(
                    button: true,
                    label: '查看${user.name}的头像详情',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => showAvatarDetails(value, user.name),
                      child: ProtectedAvatar(
                        name: user.name,
                        attachmentId: value.fields['avatarAttachmentId'] as String?,
                        radius: 42,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('${department ?? '部门未提供'} · ${position ?? '职位未提供'}', style: const TextStyle(color: DogBrandPalette.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              if (intro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 112),
                  child: Text(intro, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('联系与资料', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        PaperSurface(
          color: DogBrandPalette.surface,
          borderColor: DogBrandPalette.line,
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < contact.length; i++) ...[
                ListTile(
                  leading: Icon(contact[i].$3, color: SunnyPalette.primaryStrong),
                  title: Text(contact[i].$1, style: const TextStyle(color: DogBrandPalette.muted, fontSize: 12)),
                  subtitle: Text(contact[i].$2 == null || '${contact[i].$2}'.trim().isEmpty ? '未提供' : '${contact[i].$2}'),
                  dense: true,
                ),
                if (i < contact.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget editableInfoField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) => SizedBox(
    width: 150,
    child: TextField(
      controller: controller,
      enabled: !saving,
      keyboardType: keyboardType,
      maxLength: switch (label) {
        '电话' => 32,
        '邮箱' => 254,
        '性别' => 20,
        _ => null,
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: '未提供',
        counterText: '',
        isDense: true,
      ),
    ),
  );

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
            icon: const Icon(Icons.edit_outlined),
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
                if (!editing) _profileOverview(context, value, user) else PaperSurface(
                  color: DogBrandPalette.surface,
                  borderColor: DogBrandPalette.line,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Semantics(
                            button: true,
                            label: '查看${user.name}的头像详情',
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => showAvatarDetails(value, user.name),
                              child: ProtectedAvatar(
                                name: user.name,
                                attachmentId:
                                    value.fields['avatarAttachmentId']
                                        as String?,
                                radius: 36,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${value.fields['departmentName'] ?? value.fields['部门'] ?? '部门未提供'} · ${value.fields['position'] ?? value.fields['职位'] ?? '职位未提供'}',
                                  style: const TextStyle(
                                    color: DogBrandPalette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 150,
                            child: infoField(
                              '职位',
                              value.fields['position'] ?? value.fields['职位'],
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: infoField(
                              '部门',
                              value.fields['departmentName'] ??
                                  value.fields['部门'],
                            ),
                          ),
                          if (editing) ...[
                            editableInfoField('电话', phone, keyboardType: TextInputType.phone),
                            editableInfoField('邮箱', email, keyboardType: TextInputType.emailAddress),
                            editableInfoField('性别', gender),
                            editableInfoField('年龄', age, keyboardType: TextInputType.number),
                          ] else ...[
                            SizedBox(
                              width: 150,
                              child: infoField(
                                '电话',
                                value.fields['phone'] ?? value.fields['手机号'],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: infoField(
                                '邮箱',
                                value.fields['email'] ?? value.fields['邮箱'],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: infoField(
                                '性别',
                                value.fields['gender'] ?? value.fields['性别'],
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: infoField(
                                '年龄',
                                value.fields['age'] ?? value.fields['年龄'],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '个人简介',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (editing)
                        TextField(
                          controller: introduction,
                          enabled: !saving,
                          maxLength: 500,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            hintText: '介绍你的工作方向与经历',
                          ),
                        )
                      else
                        Text(
                          '${value.fields['个人介绍'] ?? value.fields['body'] ?? '暂无个人简介'}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                        ),
                    ],
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
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
