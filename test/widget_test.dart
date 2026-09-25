// 应用冒烟测试。
//
// 此前这里遗留的是 Flutter 计数器模板测试（断言 find.text('0') /
// Icons.add），与本应用完全不符，导致 CI `flutter test` 必然失败
//（Actions 报错的直接原因之一）。
//
// 现替换为确定性的组件级测试：只渲染不触发网络 / 不创建 Timer 的
// 纯组件，保证 CI 稳定（首屏 HomePage 会在 initState 里发起真实
// 网络请求，因此不对整个 RootPage 做 pumpWidget 冒烟）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic/core/protocol/models.dart';
import 'package:jmcomic/pages/search/search_page.dart';
import 'package:jmcomic/state/app_state.dart';
import 'package:jmcomic/widgets/album_card.dart';
import 'package:jmcomic/widgets/feedback.dart';
import 'package:provider/provider.dart';

SearchAlbum _fakeAlbum() => SearchAlbum.fromMap(<String, dynamic>{
      'id': 422889,
      'name': '测试漫画标题',
      'author': '测试作者',
      'image': '',
      'category': <String, dynamic>{'id': '1', 'title': '同人志'},
      'category_sub': <String, dynamic>{'id': '2', 'title': '校园'},
      'update_at': 0,
    });

void main() {
  group('反馈组件（feedback.dart）', () {
    testWidgets('SectionHeader 渲染标题', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SectionHeader(title: '单元测试标题')),
      ));
      expect(find.text('单元测试标题'), findsOneWidget);
    });

    testWidgets('EmptyView 渲染空态文案', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmptyView(message: '暂无内容')),
      ));
      expect(find.text('暂无内容'), findsOneWidget);
    });

    testWidgets('Pill 渲染胶囊标签', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Pill(label: '萝莉')),
      ));
      expect(find.text('萝莉'), findsOneWidget);
    });
  });

  group('AlbumCard', () {
    testWidgets('渲染标题与作者信息', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AlbumCard(album: _fakeAlbum()),
        ),
      ));
      // 等待一帧，确保卡片布局稳定。
      await tester.pump();
      // 网格卡片：标题与作者必现。
      expect(find.text('测试漫画标题'), findsOneWidget);
      expect(find.text('测试作者'), findsOneWidget);
      // 说明：封面加载在测试的 FakeAsync 环境中不会完成（无真实 IO），
      // 因此仅断言无异常，不对封面占位的具体图标做断言。
      expect(tester.takeException(), isNull);
    });
  });

  group('SearchPage 落地页', () {
    testWidgets('不触发搜索时仅展示轻量内容', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: AppState(),
          child: const MaterialApp(home: SearchPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 精简后的落地页：热门搜索 + 搜索历史 + 提示。
      expect(find.text('热门搜索'), findsOneWidget);
      expect(find.textContaining('提示：'), findsOneWidget);
      // 输入纯数字时不展示旧版"编号直达卡片"，提交后直接跳详情。
      expect(find.text('输入漫画编号可直达详情页'), findsNothing);
    });
  });
}
