// 第三十九批契约：全角字符折叠（中文输入法下「输对了、程序说不行」）。
//
// 主类是同一件事在不同入口各写一遍：
//   1. 作者首字母：`ＡＢ` 的码点是 0xFF21，落不进 A–Z → 整个作者归 `#`；
//   2. 作者搜索：折叠了，但折叠写在剥 `@` **之后** → 全角 `＠张三` 剥不掉前缀，
//      和同目录的 `@张三` 分成两个作者；
//   3. 分类树筛选与搜索页：完全没折叠 → 搜「ＡＢ」搜不到「AB」；
//   4. 地址归一：`nas：8090`（全角冒号）被 Uri 编成 host `nas%EF%BC%9A8090`，
//      `http://nas:８０９０`（全角数字）直接判「地址不能为空」；
//   5. 序号前缀：`（１）名称` 与 `(1)名称` 是同一个编号，但 `\d` 不认全角数字。
//
// 折叠本身必须是**严格一对一**（长度不变）：调用方拿折叠串定位、切原串，
// 长度一变就会切错字符。这条是整套方案的地基，单独钉住。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_index.dart';
import 'package:shoucangjia/category_tree.dart';
import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/index_prefix.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/text_fold.dart';

void main() {
  group('foldFullWidthAscii：一对一、只折全角 ASCII', () {
    test('全角数字/字母/标点折成半角', () {
      expect(foldFullWidthAscii('（１）名称'), '(1)名称');
      expect(foldFullWidthAscii('ＡＢＣ'), 'ABC');
      expect(foldFullWidthAscii('ａｂｃ'), 'abc');
      expect(foldFullWidthAscii('：'), ':');
      expect(foldFullWidthAscii('＠'), '@');
      expect(foldFullWidthAscii('／'), '/');
      expect(foldFullWidthAscii('．'), '.');
    });

    test('全角空格折成半角空格', () {
      expect(foldFullWidthAscii('a\u3000b'), 'a b');
    });

    test('长度恒等：任何输入都不变长变短（调用方靠下标切原串）', () {
      for (final s in [
        '（１）名称',
        '＠张三',
        'ｈｔｔｐ：／／ｎａｓ：８０９０',
        '混合 ＡＢ 中文 １２３',
        '',
        '纯 ASCII 不动',
      ]) {
        expect(foldFullWidthAscii(s).length, s.length, reason: '输入「$s」');
      }
    });

    test('不折没有 ASCII 对应物的中文标点', () {
      expect(foldFullWidthAscii('、'), '、');
      expect(foldFullWidthAscii('。'), '。');
      expect(foldFullWidthAscii('中'), '中');
    });

    test('纯 ASCII 输入原样返回，不做无谓改写', () {
      const s = 'http://nas:8090/a b';
      expect(foldFullWidthAscii(s), s);
    });

    test('foldForMatch = 折叠 + 小写，只用于比较', () {
      expect(foldForMatch('ＡＢ'), 'ab');
      expect(foldForMatch('Ab'), 'ab');
    });
  });

  group('作者首字母：全角字母与全角 @ 都归到正确的组', () {
    test('全角字母归对应 A–Z，不再掉进 #', () {
      expect(authorIndexLetter('ＡＢ'), 'A');
      expect(authorIndexLetter('ｚ'), 'Z');
      expect(authorIndexLetter('ｚｚ'), 'Z');
    });

    test('全角 ＠ 前缀先折叠再剥，与半角 @ 同组', () {
      expect(authorIndexLetter('＠张三'), authorIndexLetter('@张三'));
      expect(authorIndexLetter('＠张三'), isNot('#'));
      // 连写多个（半角+全角混排）也要全剥掉。
      expect(authorIndexLetter('＠＠张三'), authorIndexLetter('张三'));
      expect(authorIndexLetter('@＠张三'), authorIndexLetter('张三'));
    });

    test('剥 @ 后为空才归 #', () {
      expect(authorIndexLetter('@'), '#');
      expect(authorIndexLetter('＠＠'), '#');
      expect(authorIndexLetter(''), '#');
    });

    test('全角数字开头仍归 #（不是字母也不是汉字）', () {
      expect(authorIndexLetter('１号'), '#');
    });
  });

  group('作者搜索：折叠与剥 @ 互不覆盖', () {
    test('全角/半角互相命中', () {
      expect(authorMatchesQuery('ＡＢ', 'ab'), isTrue);
      expect(authorMatchesQuery('AB', 'ａｂ'), isTrue);
    });

    test('全角 ＠ 作者名可被裸名搜到，反之亦然', () {
      expect(authorMatchesQuery('＠张三', '张三'), isTrue);
      expect(authorMatchesQuery('@张三', '张三'), isTrue);
      expect(authorMatchesQuery('张三', '＠张三'), isTrue);
    });

    test('空查询放行；不相关不命中', () {
      expect(authorMatchesQuery('张三', ''), isTrue);
      expect(authorMatchesQuery('张三', '   '), isTrue);
      expect(authorMatchesQuery('张三', '李四'), isFalse);
    });

    test('authorMatchKey 不改原串（只返回比较键）', () {
      const raw = '＠ＡＢ';
      expect(authorMatchKey(raw), 'ab');
      expect(raw, '＠ＡＢ');
    });
  });

  group('分类树筛选：全角输入与半角名字互通', () {
    CategoryNode tree(String name, List<String> authors, [List<CategoryNode> kids = const []]) =>
        CategoryNode(name: name, rel: 'r', authors: authors, children: kids);

    test('全角查询命中半角分类名', () {
      final t = tree('ABC', const []);
      expect(filterCategoryTree(t, 'ＡＢＣ').name, 'ABC');
      expect(filterCategoryTree(t, 'ａｂｃ').name, 'ABC');
    });

    test('半角查询命中全角分类名', () {
      final t = tree('ＡＢＣ', const []);
      expect(filterCategoryTree(t, 'abc').name, 'ＡＢＣ');
    });

    test('作者名同样折叠：全角查询命中半角作者', () {
      final t = tree('分类', const ['XYZ']);
      expect(filterCategoryTree(t, 'ｘｙｚ').authors, ['XYZ']);
      final t2 = tree('分类', const ['ＸＹＺ']);
      expect(filterCategoryTree(t2, 'xyz').authors, ['ＸＹＺ']);
    });

    test('expandedForQuery 也走同一口径', () {
      final child = CategoryNode(name: 'ＡＢ', rel: 'a/b', authors: const [], children: const []);
      final root = tree('根', const [], [child]);
      expect(expandedForQuery(root, 'ab'), contains('a/b'));
      expect(expandedForQuery(root, 'ａｂ'), contains('a/b'));
    });

    test('筛选不改写节点名的原始字符', () {
      final t = tree('ＡＢＣ', const []);
      expect(filterCategoryTree(t, 'ＡＢＣ').name, 'ＡＢＣ');
    });
  });

  group('序号前缀：全角数字是同一个编号', () {
    test('全角/半角括号式结果一致', () {
      expect(stripIndexPrefix('（１）名称'), stripIndexPrefix('(1)名称'));
      expect(stripIndexPrefix('【３】名称'), '名称');
      expect(stripIndexPrefix('［２］名称'), '名称');
    });

    test('全角顿号式剥掉', () {
      expect(stripIndexPrefix('０１、名称'), '名称');
      expect(stripIndexPrefix('０１、名称'), stripIndexPrefix('01、名称'));
    });

    test('点号式仍要求空白（全角点也要有空白才剥）', () {
      expect(stripIndexPrefix('０１． 名称'), '名称');
      expect(stripIndexPrefix('01. 名称'), '名称');
      // 无空白 = 可能是日期，不剥。
      expect(stripIndexPrefix('０１．名称'), '０１．名称');
      expect(stripIndexPrefix('2026.11.24 相册'), '2026.11.24 相册');
    });

    test('剥完为空返回原串（不产出空白词条）', () {
      expect(stripIndexPrefix('（１）'), '（１）');
      expect(stripIndexPrefix('1、'), '1、');
    });

    test('叠加前缀照常层层剥', () {
      expect(stripIndexPrefix('(1)（２） 名称'), '名称');
    });

    test('bareNameOf：@ 与序号交错剥干净（任何固定顺序都有漏项）', () {
      expect(bareNameOf('@(1)名字'), '名字');
      expect(bareNameOf('＠（１）名字'), '名字');
      expect(bareNameOf('＠＠（１）名字'), '名字');
      expect(bareNameOf('  名字  '), '名字');
      expect(bareNameOf(''), '');
    });

    test('bareNameOf 返回折叠后的比较键（不是展示名）', () {
      // 它只用于「是不是同一个名字」，输出恒为半角小写前的折叠形态；
      // 展示名必须走 stripIndexPrefix（不改原字符）。
      expect(bareNameOf('＠（１）名字'), '名字');
      expect(bareNameOf('（１）'), '(1)',
          reason: '剥空时 stripIndexPrefix 回退原串，但 bareNameOf 已先折叠');
      expect(stripIndexPrefix('（１）'), '（１）',
          reason: '展示路径保留原字符，不改写用户名字');
      // 全剥掉只剩空 → 空串，不编造名字，且不死循环。
      expect(bareNameOf('@'), '');
    });
  });

  group('同步源匹配键：全角 ＠ 不再算另一个名字', () {
    test('全角 ＠ 与半角 @ 归一后相同', () {
      expect(syncUnitKey('＠作者'), syncUnitKey('@作者'));
      expect(syncUnitKey('＠作者'), syncUnitKey('作者'));
    });

    test('全角序号前缀一并归一', () {
      expect(syncUnitKey('（１）某某'), syncUnitKey('(1)某某'));
      expect(syncUnitKey('＠（１）某某'), '某某');
    });

    test('大小写与首尾空白归一', () {
      expect(syncUnitKey('  DouYin  '), 'douyin');
    });
  });

  group('地址归一：全角输入等价于半角', () {
    test('全角冒号', () {
      expect(normalizeBase('http://nas：8090'), 'http://nas:8090');
    });

    test('全角数字端口', () {
      expect(normalizeBase('http://nas:８０９０'), 'http://nas:8090');
    });

    test('整串全角（协议/冒号/斜杠/端口）', () {
      expect(normalizeBase('ｈｔｔｐ：／／ｎａｓ：８０９０'), 'http://nas:8090');
    });

    test('路径段不被改写：只清洗主机段', () {
      expect(normalizeBase('http://nas:８０９０/p a t h'), 'http://nas:8090/p a t h');
      expect(normalizeBase('http://nas/目录 名'), 'http://nas/目录 名');
    });

    test('全角斜杠作分隔符时不能把路径粘到主机上', () {
      // `／`（U+FF0F）在中文输入法里就是斜杠。旧实现只折叠不归一分隔符：
      // `http://nas／8090` 的 host 变成 `nas%EF%BC%8F8090`（合法但永远连不上），
      // `http://nas：8090／path` 直接解析失败 → 用户看到「地址不能为空」。
      expect(normalizeBase('http://nas／8090'), 'http://nas/8090');
      expect(normalizeBase('http://nas：8090／path'), 'http://nas:8090/path');
      final u = Uri.parse(normalizeBase('http://nas：8090／path'));
      expect(u.host, 'nas');
      expect(u.port, 8090);
      expect(u.path, '/path');
    });

    test('分隔符之后的字符（路径内容）不被改写', () {
      expect(normalizeBase('http://nas:8090/ａ／ｂ'), 'http://nas:8090/ａ／ｂ');
    });

    test('全角输入也要过同一套校验（不会因折叠而放过坏地址）', () {
      expect(normalizeBase('http://ｎａｓ：０'), '');
      expect(normalizeBase('http://ｎａｓ：６５５３６'), '');
      expect(normalizeBase('ｈｔｔｐ：／／'), '');
    });

    test('非 http(s) 协议不猜着改写', () {
      expect(normalizeBase('ｆｔｐ：／／nas'), '');
      expect(normalizeBase('ftp://nas'), '');
    });
  });

  group('契约扫描：折叠只许有一个实现', () {
    final lib = Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (f.path.split('/').last, f.readAsStringSync()))
        .toList();

    String srcOf(String name) =>
        lib.firstWhere((e) => e.$1 == name, orElse: () => ('', '')).$2;

    test('全角折叠常量只在 text_fold.dart 出现', () {
      // 0xFEE0 / 0xFF01 / 0x3000 是折叠的实现细节；别处再写一遍就是第二套口径。
      for (final (name, src) in lib) {
        if (name == 'text_fold.dart') continue;
        expect(src.contains('0xFEE0'), isFalse, reason: '$name 里又写了一遍折叠偏移');
      }
    });

    test('各搜索入口都必须走折接口，不能裸 toLowerCase().contains', () {
      // 分类树
      final cat = srcOf('category_tree.dart');
      expect(cat.contains("node.name.toLowerCase().contains(q)"), isFalse,
          reason: '分类树筛选又回到裸小写比较');
      expect(cat.contains('foldForMatch'), isTrue);

      // 作者索引
      final au = srcOf('author_index.dart');
      expect(au.contains("replaceFirst(RegExp(r'^@+'), '')"), isFalse,
          reason: '剥 @ 必须与折叠合并（全角 ＠ 否则漏掉）');

      // 搜索页
      final main = srcOf('main.dart');
      expect(main.contains("'\${w['ti']}'.contains(kw)"), isFalse,
          reason: '搜索页又回到裸 contains');

      // 同步源键
      final cs = srcOf('collection_sync.dart');
      expect(cs.contains("while (s.startsWith('@'))"), isFalse,
          reason: 'syncUnitKey 又自己剥 @（不折叠就漏全角 ＠）');
      expect(cs.contains('bareNameOf'), isTrue,
          reason: 'syncUnitKey 必须交错剥 @ 与序号，否则 @(1)名字 / ＠（１）名字 有一条漏');
    });

    test('text_fold 不导出「是否含全角」这类零调用面', () {
      final src = srcOf('text_fold.dart');
      expect(src.contains('bool hasFullWidthAscii'), isFalse,
          reason: '零调用成员应删除（死实现会被误当成第二套判定）');
    });

    test('折叠注明只用于比较，不得用于回写', () {
      final src = srcOf('text_fold.dart');
      expect(src.contains('只用于比较'), isTrue);
      expect(src.contains('长度不变'), isTrue);
    });
  });
}
