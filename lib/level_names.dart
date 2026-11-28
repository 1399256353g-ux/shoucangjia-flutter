/// 四个层级的中文叫法（**唯一一份**）。
///
/// 0.9.359：同一套「层级 → 中文名」在设置页里存在两份互不相干的表：
///
/// ```
/// main.dart  _CornerBadgeSettingsPageState._kindLabels   媒体库/单元库/基础库
/// main.dart  _entryStyleSection.labels                   媒体库/单元库/基础库/作者
/// ```
///
/// 两份都「看起来正常」，于是改名时只会改到其中一处：角标页写着「媒体库」、
/// 词条外观页也写着「媒体库」，但外加作者一档只有后一份有；再往下，
/// 作者筛选摘要（`author_filter.summary`）又各自写死 `'媒体库'` / `'单元库'` /
/// `'基础库'` 三个字面量——同一个筛选条件在摘要与面板里可以叫两个名字。
///
/// 术语按 PROJECT_RULES 第一节：日常/界面一律叫「媒体库」（`top`），
/// 「顶级单元库」只在设计结构设置页内部使用。
library;

import 'library_badge.dart' show LibEntryKind;

/// 层级 → 界面文案。键就是词条层级，避免再出现第二套层级枚举。
const Map<LibEntryKind, String> kLevelNames = <LibEntryKind, String>{
  LibEntryKind.top: '媒体库',
  LibEntryKind.unit: '单元库',
  LibEntryKind.basic: '基础库',
  LibEntryKind.author: '作者',
};

/// 取某层级的中文名；未知层级回落枚举名（不编造文案）。
String levelName(LibEntryKind kind) => kLevelNames[kind] ?? kind.name;

/// 「不属于任何媒体库」那一节的名字（**唯一一份**）。
///
/// 0.9.360：这句在三个地方各写了一遍——`crawler_sections.CrawlerSection.title`
/// 的默认值、库词条配色页的节标题、爬虫设置页「其它」节标题。改一个字的
/// 时候只会改到其中一处，同一个节在三个页面上就可能有三个名字。
const String kOtherSectionTitle = '其它（不属于任何媒体库）';
