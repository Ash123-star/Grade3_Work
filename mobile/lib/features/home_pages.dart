import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cute_ui/cute_ui.dart';
import '../core/providers.dart';
import '../data/models.dart';
export 'ai_map_page.dart';
export 'dashboard_page.dart';
import '../shared/widgets.dart';
import 'demo_pages.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  bool team = false;
  String? member;
  @override
  Widget build(BuildContext context) {
    final user=ref.watch(sessionProvider);
    final date=ref.watch(logFilterDateProvider);
    final editDate=date??DateTime.now();
    final subordinate=team && user.manager;
    final resource=subordinate?'logs/subordinates':'logs';
    final owner=subordinate?member:user.id;
    final data=ref.watch(logDayRecordsProvider((resource,owner)));
    final existing=data.valueOrNull?.items.where((r)=>r.fields['businessDate']==editDate.toIso8601String().split('T').first).firstOrNull;
    void edit() {
      ref.read(logDateProvider.notifier).state=editDate;
      openForm(context,existing==null?'log-edit':'log-revise',id:existing?.id,version:existing?.version);
    }
    return PageFrame(title:'工作日志',child:PageBody(children:[
      const DemoLabel(),
      if(user.manager) SegmentedButton<bool>(segments:const [ButtonSegment(value:false,icon:Icon(Icons.edit_note),label:Text('我的日志')),ButtonSegment(value:true,icon:Icon(Icons.groups_outlined),label:Text('下属日志'))],selected:{subordinate},onSelectionChanged:(s)=>setState(()=>team=s.first)),
      const SizedBox(height:16),
      if(subordinate) ...[
        ref.watch(recordsProvider('organization')).when(loading:()=>const LinearProgressIndicator(),error:(e,s)=>ErrorPanel('$e',retry:()=>ref.invalidate(recordsProvider('organization'))),data:(page)=>DropdownButtonFormField<String>(
          key:ValueKey('$member:${user.id}'),initialValue:page.items.any((r)=>r.id==member)?member:null,
          decoration:const InputDecoration(labelText:'选择下属',prefixIcon:Icon(Icons.person_outline)),
          items:[const DropdownMenuItem(value:null,child:Text('全部下属')),for(final person in page.items) if(person.id!=user.id) DropdownMenuItem(value:person.id,child:Text(person.title))],
          onChanged:(v)=>setState(()=>member=v))),const SizedBox(height:12),
      ],
      OutlinedButton.icon(icon:const Icon(Icons.calendar_today_outlined),label:Text(date==null?'全部日期 · 按日期筛选':'${date.year}年${date.month}月${date.day}日'),onPressed:() async {
        final next=await showDatePicker(context:context,initialDate:date??DateTime.now(),firstDate:DateTime(2020),lastDate:DateTime(2040));
        if(next!=null) ref.read(logFilterDateProvider.notifier).state=next;
      }),
      if(date!=null) TextButton.icon(onPressed:()=>ref.read(logFilterDateProvider.notifier).state=null,icon:const Icon(Icons.clear),label:const Text('全部日期')),
      const SizedBox(height:16),
      if(!subordinate) ...[
        FilledButton.icon(onPressed:data.isLoading||data.hasError?null:edit,icon:const Icon(Icons.edit_outlined),label:Text(existing==null?'编辑并提交日志':'编辑已提交日志')),
        const SizedBox(height:8),const Text('编辑时自动保存草稿；已提交的日志修改后进入审核。',style:TextStyle(color:CuteTokens.muted)),
      ],
      SectionHeader(subordinate?'下属日志列表':'我的日志列表'),
      data.when(loading:()=>const LoadingSkeleton(),error:(e,s)=>ErrorPanel('$e',retry:()=>ref.invalidate(logDayRecordsProvider)),data:(page){
        final items=page.items.where((r)=>!subordinate||r.ownerId!=user.id).toList();
        if(items.isEmpty) return EmptyIllustration(title:date==null?'暂无日志':subordinate?'所选日期暂无下属日志':'这一天还没有提交日志',subtitle:subordinate?'可以更换人员或日期查看':'点击上方按钮填写并提交');
        return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[for(final r in items) Padding(padding:const EdgeInsets.only(bottom:12),child:CuteCard(onTap:()=>openItem(context,resource,r.id),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(r.title,style:Theme.of(context).textTheme.titleMedium),const SizedBox(height:8),Text(r.subtitle),const SizedBox(height:8),Text('${r.fields['今日工作']??r.fields['body']??''}'),const SizedBox(height:8),StatusPill('${r.fields['status']??'已提交'}'),const SizedBox(height:8),const Text('查看完整日志 ›',style:TextStyle(color:Colors.teal))]))) ]);
      }),
      if(!subordinate) TextButton.icon(onPressed:()=>context.push('/conflict'),icon:const Icon(Icons.history),label:const Text('继续编辑草稿')),
    ]));
  }
}

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});
  @override
  Widget build(BuildContext context) => const PageFrame(
    title: '时间视图',
    child: PageBody(children: [DemoLabel(), DateControls(), CalendarContent()]),
  );
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    Widget link(String title, IconData icon, VoidCallback tap) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: tap,
    );
    return PageFrame(
      title: '我的',
      actions: [
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      child: PageBody(
        children: [
          const DemoLabel(),
          const CuteArt('1F331', size: 80),
          const SizedBox(height: 16),
          Center(
            child: Text(
              user.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 6),
          Center(child: Text('产品部 · 体验团队 · ${user.role.label}')),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${ref.watch(itemProvider(('organization/profile', user.id))).valueOrNull?.fields['个人介绍'] ?? '认真工作，也记得好好生活。'}',
            ),
          ),
          TextButton(
            onPressed: () => openForm(context, 'profile-edit'),
            child: const Text('编辑个人资料'),
          ),
          const Divider(),
          link('我的任务', Icons.task_alt, () => openList(context, 'tasks')),
          link(
            '个人重点',
            Icons.star_border,
            () => openList(context, 'dashboard/personal'),
          ),
          link(
            '消息中心',
            Icons.notifications_none,
            () => openList(context, 'notifications'),
          ),
          if (user.manager) ...[
            const SectionHeader('团队管理'),
            link(
              '审批',
              Icons.fact_check_outlined,
              () => openList(context, 'reviews'),
            ),
            link(
              '组织与成员',
              Icons.account_tree_outlined,
              () => openList(context, 'organization'),
            ),
            link('工作统计', Icons.bar_chart, () => context.push('/analytics')),
          ],
          if (user.administrator) ...[
            link(
              '组织与权限设置',
              Icons.admin_panel_settings_outlined,
              () => context.push('/admin'),
            ),
            link('审计记录', Icons.manage_search, () => openList(context, 'audit')),
          ],
          link('帮助与反馈', Icons.help_outline, () => context.push('/help')),
          link(
            '我的申请',
            Icons.fact_check_outlined,
            () => openList(context, 'reviews'),
          ),
          const SectionHeader('工作动态'),
          const RecordList('logs', limit: 2),
        ],
      ),
    );
  }
}
