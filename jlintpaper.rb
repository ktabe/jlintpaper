#!/usr/bin/ruby
# -*- coding: utf-8 -*-
#coding: utf-8
#
# Description:
#
# LaTeXで書かれた日本語の論文やレポートをチェックし，正しくない可能性
# がある箇所を指摘します．間違った指摘があることに注意して下さい．
# 
# 実行には ruby version 2 以降が必要です．
#
# 使い方: ruby jlintpaper.rb file-to-check.tex
#
# Web site: <http://github.com/ktabe/jlintpaper/>
#
# Copyright 2016-2023 (C) Kota Abe
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

if RUBY_VERSION < '2.0.0'
  abort 'require ruby 2.0 or later'
end

require 'nkf'
require 'optparse'

$VERSION = '0.3.0'
$debug = false

$marker_mono = ['>>>', '<<<']
$marker_color = ["\e[45m", "\e[0m"] # マジェンタ

# 対応する(カッコ)にマッチする正規表現
paren = '(?<paren>
  \(([^()（）]|\g<paren>)*\)
 |
 （([^()（）]|\g<paren>)*）
)'

# 対応する`引用符'にマッチする正規表現
quote = '(?<quote>
  `([^`\']|\g<quote>)*\'
)'

# rubyの正規表現メモ:
# (?=pat) 肯定先読み(positive lookahead)
# (?!pat) 否定先読み(negative lookahead)
# (?<=pat) 肯定後読み(positive lookbehind)
# (?<!pat) 否定後読み(negative lookbehind)

# 原則として平仮名で表記する語句
ieiceURL = 'http://www.ieice.org/jpn/shiori/pdf/furoku_d.pdf'
# こと（許可しないことがある）
# もの（正しいものと認める）
# とも（説明するとともに意見を聞く）
# ゆえ（一部の反対のゆえにはかどらない）
# わけ（賛成するわけにはいかない）
# 此→この
# 之→これ
# 其→その
# 為→ため
# 虞→おそれ
# 又→また（山また山）
nokanji = '事物共故訳此之其為虞又'
# nokanji = '挙'

# 段落に対するチェック
$regexp_p = [
  # 文字
  {'regexp'=>/[０-９Ａ-Ｚａ-ｚ]/, 'desc'=>'全角英数字は使わない'},
  {'regexp'=>/\p{^ascii}[.,]/, 'desc'=>'日本語文字のあとに半角カンマやピリオド（原則全角）'},
  {'regexp'=>/(?<!\\),(?![\d\s'"}])/, 'desc'=>',の後に空白がない'},
  {'regexp'=>/
  (?:\p{^ascii})[ \t]+(?:\p{^ascii})
  |(?<=[．。、，])[ \t]+(?=\p{ascii})
  |(?<=\p{ascii})[ \t]+(?=[．。、，])
  /x, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/[“”"]/, 'desc'=>'ダブルクォーテーションは使わない(代わりに``と\'\'を使う．プログラムリストではOK)'},

  # 相互参照
  {'regexp'=>/(^|[^図表式\s])\s*\\ref\{[^}]*\}(?![節章項])/, 'desc'=>'\\refの前後に図・表・式あるいは章・節・項がない'},
  {'regexp'=>/[.\d]+\s*[章節項]|[図表]\s*\d+|(?<!方)式\s*\d+/, 'desc'=>'章や節，図表式番号を直接指定している?(\\refを使うべき)'},
  {'regexp'=>/[.\d]+\s*で(前|後)?述/, 'desc'=>'章や節番号を直接記述している?(「\\ref{..}章」のように書くべき)'},

  # 漢字とひらがな
  # とき（事故のときは連絡する）
  # とおり（次のとおりである）
  # ある（その点に問題がある）
  # いる（ここに関係者がいる）
  # なる（合計すると１万円になる）
  # できる（誰でも利用ができる）
  # ……てあげる（図書を貸してあげる）
  # ……ていく（負担が増えていく）
  # ……ておく（通知しておく）
  # ……てくる（寒くなってくる）
  # ……てしまう（書いてしまう）
  # ……てみる（見てみる）
  # ない（現地には行かない）
  # ようだ（それ以外に方法がないようだ）
  # ぐらい（二十歳ぐらいの人）
  # だけ（調査しただけである）
  # ほど（三日ほど経過した）
  # 以って→もって
  # 且つ→かつ
  # 但し→ただし
  # 但書→ただし書
  # 従って（接続詞）→したがって
  # 因る→よる
  # ほか（特別の場合を除くほか）
  # 外→ほか
  {'regexp'=>/(
    全て
    |(?<=の)時(?![点間計刻])
    |の通り
    |有る|在る|居る|成る
    |出来
    |て上げる|て行く|て置く|て来る|て仕舞う|て見る
    |無い
    |\p{^Han}様\p{Hiragana}
    |\p{^Han}位\p{^Han}
    |丈
    |程(?!度)
    |以って
    |且つ
    |但し|但(?=書)
    |従って
    |因る
    |(?<!その)他[^の\p{Han}\p{Katakana}]
    |(?<![の\p{Han}])外[^\p{Han}れ]     # 「ほか」と読む場合
    |(?<=[^カ\p{Han}])所(?=\p{^Han})    # ところ（現在のところ差し支えない）
    |(?<![均同冪平対])等(?=[^し\p{Han}])  # 等→ら
    |(?<=\p{^Han}|^)[#{nokanji}](?=\p{^Han})
    )/x,
    'desc'=>"原則として平仮名で表記すべき語句 (cf. #{ieiceURL})"},
  {'regexp'=>/[一二三四五六七八九〇][つ個]/, 'desc'=>'一つ，二つなどが数値を表す場合はアラビア数字を用いる(日本語の言い回しならばOK)'},
  {'regexp'=>/同士/, 'desc'=>'同士→どうし'},
  {'regexp'=>/わかる/, 'desc'=>'わかる→分かる'},
  {'regexp'=>/\p{Hiragana}上で/, 'desc'=>'上で→うえで（「上で」を「うえで」と読む場合）'},
  {'regexp'=>/押さえ/, 'desc'=>'押さえ→おさえ'},
  {'regexp'=>/例え/, 'desc'=>'例え→たとえ'},
  {'regexp'=>/或/, 'desc'=>'或→あるい'},
  {'regexp'=>/行な/, 'desc'=>'行な→行（「な」は送らない）'},
  {'regexp'=>/オーバー/, 'desc'=>'オーバー→オーバ'},
  {'regexp'=>/タイマー/, 'desc'=>'タイマー→タイマ'},
  {'regexp'=>/インターフェイス/, 'desc'=>'インターフェイス→インタフェース'},

  # 表現
  {'regexp'=>/(です|ます|でしょう)[.．。が]/, 'desc'=>'「です・ます」調は使わない．「だ・である」調を使う（謝辞の中は良い）．'},
  {'regexp'=>/が，/, 'desc'=>'気をつけるべき表現（接続助詞の「が」）'},
  {'regexp'=>/考えられる/, 'desc'=>'気をつけるべき表現（考えられる）'},
  {'regexp'=>/そして/, 'desc'=>'原則として避けるべき語句（そして）'},
  {'regexp'=>/が[わ分]かる/, 'desc'=>'原則として避けるべき表現（がわかる）'},
  {'regexp'=>/のだ[．。]/, 'desc'=>'避けるべき表現「〜のだ．」→「〜のである．」'},
  {'regexp'=>/(なので|だから)/, 'desc'=>'口語表現「なので」「だから」→「であるため」'},
  {'regexp'=>/いけない/, 'desc'=>'口語表現（いけない）'},
  {'regexp'=>/(?<!して|こと)から[,，、]/, 'desc'=>'口語表現 「から」（理由を表す場合）→「ため」'},
  {'regexp'=>/いい/, 'desc'=>'口語表現「いい」→「よい」'},
  {'regexp'=>/けど/, 'desc'=>'口語表現「けど」→「が」'},
  {'regexp'=>/っ?たら/, 'desc'=>'口語表現「たら」→「ると」「れば」「る場合」「た場合」など'},
  {'regexp'=>/いろんな/, 'desc'=>'口語表現「いろんな」→「様々な」'},
  {'regexp'=>/((?<=が)い|要)(ら|り|る)/, 'desc'=>'口語表現「いる」→「必要とする」'},
  {'regexp'=>/とっ?ても/, 'desc'=>'口語表現「とても」→「非常に」'},

  {'regexp'=>/をする/, 'desc'=>'「をする」→「する」or「を行う」(?)'},
  {'regexp'=>/をして/, 'desc'=>'「をして」→「して」or「を行なって」(?)'},
  {'regexp'=>/することができ(る|ない)/, 'desc'=>'「することができる」「することができない」→「できる」「できない」(?)'},
  {'regexp'=>/することが可能/, 'desc'=>'「することが可能」→「できる」(?)'},
  {'regexp'=>/なので/, 'desc'=>'「なので」→「であるため」or「ので」(?)'},
  # :数字 はポート番号などで使われるので除外
  {'regexp'=>/(?<!:)\d{4,}(?!年)/, 'desc'=>'大きな数字には3桁ごとにカンマを入れる(?)'},

  # 書き間違え
  {'regexp'=>/郡/, 'desc'=>'群の間違い(?)'},
  {'regexp'=>/自立/, 'desc'=>'自律の間違い(?)'},
  {'regexp'=>/対故障性/, 'desc'=>'耐故障性の間違い(?)'},
  {'regexp'=>/上げられる/, 'desc'=>'挙げられるの間違い(?)'},
  {'regexp'=>/[^にてでがり]行われる/, 'desc'=>'「行われる」の前が変(?)'},
  {'regexp'=>/[^\p{Han}にてでがらをりも]行う/, 'desc'=>'「行う」の前が変(?)'},
  # するための，用いるための，作るための -> OK
  # 行わないための，用いないための -> OK
  # 行わせるための，行わせないための -> OK
  # このための，示すための，埋め込むための -> OK
  {'regexp'=>/(?<!る|ない|の|す|む|行う)ための/, 'desc'=>'「ための」の前が変(?)'},
  {'regexp'=>/をは/, 'desc'=>'をは(書き間違い?)'},
  {'regexp'=>/しように/, 'desc'=>'しように(書き間違い?)'},

  # 中国人留学生の典型的な間違い
  # ここでは「ないの」は除外し，次でチェック
  {'regexp'=>/(?<!互|くら|ぐら|な)いの(?!だが)/, 'desc'=>'形容詞の後に余分な「の」(?)'}, ## 等しいのため
  # 「ないので」はOK
  {'regexp'=>/(?<=ない)の(?!で)/, 'desc'=>'「ないの」→「ない」(?)'}, ## 少ないの場合
  {'regexp'=>/(?<=い)だ(?=と)/, 'desc'=>'形容詞の後に余分な「だ」(?)'},  ## 少ないだと
  #  {'regexp'=>/(?<=る)の(?!\p{Hiragana})/, 'desc'=>'余分な「の」(?)'},   ## いるの場合
  {'regexp'=>/(?<=る)の(?![かにはで])/, 'desc'=>'余分な「の」(?)'},   ## いるの場合

  # 括弧の対応
  {'regexp'=>/（\p{ascii}*）/, 'desc'=>'全角括弧内が半角文字のみ(半角括弧にする?)'},
  {'regexp'=>/\((?=  ([^()（）]|#{paren})*  \Z)/xm, 'desc'=>'半角(に対応する)がない'},
  {'regexp'=>/（(?=  ([^()（）]|#{paren})*  \Z)/xm, 'desc'=>'全角（に対応する）がない'},
  {'regexp'=>/\A   ([^()（）]|#{paren})*\)/xm, 'desc'=>'半角)に対応する(がない'},
  {'regexp'=>/\A   ([^()（）]|#{paren})*）/xm, 'desc'=>'全角）に対応する（がない'},
  {'regexp'=>/\(  ([^()（）]|#{paren})*  ）/xm, 'desc'=>'半角(と全角）が対応'},
  {'regexp'=>/（  ([^()（）]|#{paren})*  \)/xm, 'desc'=>'全角（と半角)が対応'},
  {'regexp'=>/`(?=  ([^`\']|#{quote})*  \Z)/xm, 'desc'=>'`(左引用符)に対応する\'(右引用符)がない'},
  {'regexp'=>/\A  ([^`\']|#{quote})*    \'/xm, 'desc'=>'\'(右引用符)に対応する`(左引用符)がない'},
]

# 文に対するチェック
$regexp_s = [
  # 表記
  {'regexp'=>/(?<!。|．|\.|\?|\)|\\hline|}|\]|\\\\)\s*$/, 'desc'=>'文末に句点やピリオドがない'},
  {'regexp'=>/^\s*[，、．。]/, 'desc'=>'文頭が句読点類から始まっている'},
  # {'regexp'=>/(\p{Han}|\p{Katakana}|[A-Za-z0-9])[.．。]$/, 'desc'=>'体言止め(?)'},
  {'regexp'=>/(?<![うくすつぶむるいた）)}])[.．。]$/, 'desc'=>'文の終わり方がおかしい?(体言止め?)'},
  {'regexp'=>/[^\P{Hiragana}かがたはばやらいきしちにびみりくつすずえけげせてでへべめれおもとどのろを][，、]/, 'desc'=>'読点の前がおかしい(?)'},
  {'regexp'=>/は[，、].*はある[．。]$/, 'desc'=>'〜は，〜はある'},
  {'regexp'=>/^.{100,}/, 'desc'=>'長い文は避ける(100文字以上をマーク)'},
  # 以下は問題ない場合も多い
  {'regexp'=>/(\p{Han}\p{Han})する[^，、]*\1/, 'desc'=>'「検索するために検索」のように同じサ変動詞が2回現れている(?)'},
  # {'regexp'=>/を行う/, 'desc'=>'を行う→する(?)'},
  {'regexp'=>/で[，、].*で[，、]/, 'desc'=>'「で，」が連続'},
  {'regexp'=>/(?<![にで])は[，、].*(?<![にで])は[，、]/, 'desc'=>'「は，」が連続'},
  {'regexp'=>/[^いる]が[，、].*[^いる]が[，、]/, 'desc'=>'接続助詞「が，」が多用されている'},
  {'regexp'=>/際に.*際に/, 'desc'=>'「際に」が連続'},
  {'regexp'=>/場合.*場合/, 'desc'=>'「場合」が連続'},
  {'regexp'=>/対し.*対し/, 'desc'=>'「対し」が連続'},
  {'regexp'=>/ため.*ため/, 'desc'=>'「ため」が連続'},
  # 「対し」だけ例外扱い
  {'regexp'=>/(?<!対)([いきしちにひみり])[，、].*\1[，、]/, 'desc'=>'「〜し，〜し，」のように同じ「い段」の文字が読点の前で連続'},
  # 数式モードの中で連続する2文字以上の単語にマッチ
  # \Gは前回マッチ位置の直後にマッチ．$~$が1行に複数あった場合への対策
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b[A-Za-z]{2,}[^$]*\$/, 'desc'=>'$log$のように書いた場合，l*o*gという意味．関数ならば\log，イタリックならば\textit{abc}を使う'},
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b,[0-9]{3}\b[^$]*\$/, 'desc'=>'数式モードの中で大きな数の桁区切りは{,}を使う'},
]

# 行番号部分にマッチする正規表現
$header_line_regexp = '^\d+:'
$header_lines_regexp = '^\d+(\.\.\d+)?:'

def add_line_number(t, start_line, end_line = 0)
  if start_line == end_line || end_line == 0 then
    "#{start_line}:#{t}"
  else
    "#{start_line}..#{end_line}:#{t}"
  end
end

def get_line_number(t)
  # print "get_line_number: #{t}\n"
  md = t.match(/^(\d+):(.*)/)
  if md then
    return md[1].to_i, md[2]
  else
    abort "no line number! #{t}"
  end
end

def mark_text(t)
  if $mono then
    "#{$marker_mono[0]}#{t}#{$marker_mono[1]}"
  else
    "#{$marker_color[0]}#{t}#{$marker_color[1]}"
  end
end

def add_filename!(t, filename)
  if filename != nil then
    t.gsub!(/(#{$header_lines_regexp})/, "#{filename}:\\1")
  end
end

# 1つの段落を表すクラス
class Paragraph
  attr_reader :paragraph
  attr_reader :sentences
  def initialize(para)
    @paragraph = para
    split_to_sentences()
  end
  def to_s
    "#{@paragraph}"
  end

  # 段落を文に分割する
  def split_to_sentences
    print "split_to_sentences[#{to_s()}]\n" if $debug
    @sentences = []
    lnum = lstart = 0
    remain = ''
    @paragraph.each_line do |l|
      lnum, l = get_line_number(l)
      #print "lnum=#{lnum}, lstart=#{lstart}, remain=#{remain}, l=[#{l}]\n"
      lstart = lnum if remain == ''
      l = l.strip
      if remain =~ /\p{^ascii}$/ && l =~ /^\p{^ascii}/ then
        # 日本語の継続行
        remain << l
      else
        remain << " " << l
      end
      while /.*?([．。?？])/m =~ remain do
        #print "remain[" + remain + "]"
        remain = $'
        add_sentence($&, lstart, lnum)
        lstart = lnum
      end
    end
    add_sentence(remain, lstart, lnum)
  end

  def add_sentence(s, line_start, line_end)
    # p "add_sentence", line_start, line_end, s
    return if s == ''
    obj = Sentence.new(s, line_start, line_end)
    @sentences << obj
  end

  def check_paragraph
    lnum, line = get_line_number(@paragraph)
    $regexp_p.each {|c|
      if c['regexp'] =~ line then
        tmp = line.gsub(c['regexp'], mark_text('\&'))
        tmp = add_line_number(tmp, lnum)
        c['match'] <<= tmp.gsub(/\n/, "\n") + "\n";
      end
    }
  end
end

# 1つの文を表すクラス
class Sentence
  attr_reader :sentence
  attr_reader :line1
  attr_reader :line2
  def initialize(sentence, line1, line2)
    @sentence = sentence
    @line1 = line1
    @line2 = line2
  end

  def to_s
    add_line_number(@sentence, @line1, @line2)
  end

  def check_sentence
    return if /\A\s*\Z/ =~ @sentence

    $regexp_s.each do |c|
      if c['regexp'] =~ @sentence then
        tmp = @sentence.gsub(c['regexp'], mark_text('\&'))
        c['match'] <<= add_line_number(tmp.gsub(/\n/, '') + "\n", @line1, @line2)
      end
    end
  end
end

def prepare(texts)
  # 行番号を行頭に付与
  t = texts.split(/(?<=\n)/)
    .each.with_index(1)
    .map {|l, index| add_line_number(l, index)}
    .join("") << "\n"

  # *? は最小量指定子
  # % 以降を削除 (\% を除く)
  t.gsub!(/(?<!\\)%.*?$/m, '')

  # \begin{document}までを削除
  t.gsub!(/.*\\begin{document}.*?$/m, '')
  # \end{document}以降を削除
  t.gsub!(/\\end{document}.*/m, '')

  # \newcommandを削除 (複数行に渡る場合は無理)
  t.gsub!(/\\newcommand\*?{.*?$/m, '')

  # \defを削除 (複数行に渡る場合は無理)
  t.gsub!(/\\def\\.*?$/m, '')

  # \\TODO{...}を削除
  t.gsub!(/\\TODO{.*?}/m, '')

  # \begin{verbatim}〜\end{verbatim}を削除
  t.gsub!(/\\begin{verbatim}.*?\\end{verbatim}.*?/m, '')

  # \begin{comment}〜\end{comment}を削除
  t.gsub!(/\\begin{comment}.*?\\end{comment}.*?/m, '')

  # \cite{}の内部をチェックしないようにマスク
  t.gsub!(/(?<=\\cite{)[^}]*(?=})/, '**')

  # 以上の処理で空行になった行を削除
  t.gsub!(/^$\n/, '')

  # ピリオド・カンマと句読点の数をそれぞれ数える
  t.each_line do |s|
    if /[．，]/ =~ s then
      $zperiod += 1
      $zpline << s
    end
    if /[。、]/ =~ s then
      $zkuten += 1
      $zkline << s
    end
  end
  p t if $debug
  t
end

def split_to_paras(texts)
  # remove figures and tables
  texts = texts.gsub(
    /^#{$header_line_regexp}\s*?\\begin{(figure|table)\*?}
    .*?
    \\end{(figure|table)\*?}.*$
    /mx, '')

  empty_line = "#{$header_line_regexp}\s*\n"

  # まず，空行で分割
  chunks = texts.split(/\n(?:#{empty_line})+/)

  paras = []
  # それぞれのchunkは複数の段落を含む可能性があるので，ざっくり分割する
  chunks.each do |chunk|
    cont = ''
    chunk.each_line do |line|
      # puts "line=[#{line}]" if $debug
      lnum, text = get_line_number(line)
      text << "\n"
      frags = text.split(/
        # 肯定先読み (?=pat)   キャプチャしない (?:pat)
        (?:
        \\item
        |\\(?:begin|end|chapter|(?:sub)*section\*?|paragraph|vspace)\{.*?\}
        |\\par
        |\\newpage
        |\\clearpage
        |\\cleardoublepage
        )/mx)
      # cont = "100:text1\n"
      # line = "101:text2 <SEP> text3 <SEP> text4"
      # text = "text2 <SEP> text3 <SEP> text4\n"
      # frags = "text2", "text3", "text4\n"
      # last = "100: text4"
      last = frags.pop
      last = add_line_number(last, lnum)
      frags.each do |s|
        # p s if $debug
        s = add_line_number(s, lnum)
        cont << s
        if cont !~ /#{$header_line_regexp}\s*$/ then
          # p "para1", cont if $debug
          paras << Paragraph.new(cont)
        end
        cont = ''
      end
      cont = last
    end
    if cont !~ /#{$header_line_regexp}\s*$/ then
      # puts "para2: #{cont}" if $debug
      paras << Paragraph.new(cont)
    end
  end
  if $debug then
    puts "[paragraphs]"
    puts paras.join("-----\n")
  end
  paras
end

def print_regexp_check_results(filename)
  $regexp_p.each {|c|
    match = c['match']
    if match != '' then
      add_filename!(match, filename)
      print "=== " + c['desc'] + " ===\n" + match + "\n"
    end
  }
  $regexp_s.each {|c|
    match = c['match']
    if match != '' then
      add_filename!(match, filename)
      print "=== " + c['desc'] + " ===\n" + match + "\n"
    end
  }
end

def print_kutouten_check_results(filename)
  if $zkuten > 0 && $zperiod > 0 then
    print "=== 句読点（。、）と全角のカンマ・ピリオド（．，）が混在 ===\n"
    print "- 全角ピリオドあるいはカンマを含む行数: #{$zperiod}\n"
    print "- 句読点を含む行数: #{$zkuten}\n"
    add_filename!($zkline, filename)
    add_filename!($zpline, filename)
    if 0 < $zkuten && $zkuten <= $zperiod then
      print "--- 句読点が使われている行 ---\n" + $zkline + "\n"
    end
    if 0 < $zperiod && $zperiod < $zkuten then
      print "--- 全角ピリオドあるいはカンマが使われている行 ---\n" + $zpline + "\n"
    end
  end
end

# check figure and table environments
def check_figure_and_table(s, filename)
  labels = {}
  warn = ''
  s.scan(/(#{$header_line_regexp}\s*\\begin\{(figure|table)\*?\}(\[.*?\])?\s*(.*?)\\end\{\2\*?\})/m) do |match|
    env, type, opt, content = match
    w = ''
    if /\\caption/ !~ content then
      w << "--- #{type}環境に\\captionがない ---\n"
    end
    if type == 'figure' && /\\caption.*\\includegraphics/m =~ content then
      w << "--- 図のキャプションは図の下に置く ---\n"
    end
    if type == 'table' && /\\begin{tabular}.*\\caption/m =~ content then
      w << "--- 表のキャプションは表の上に置く ---\n"
    end
    if /\\label{(.*?)}/ !~ content then
      w << "--- #{type}環境に\\labelがない ---\n"
    else
      labels[$1] = true
    end
    if /\\ecaption\{([^}]*[^.])\}/ =~ content then
      w << "--- 英語キャプション(ecaption)の最後はピリオドが必要 ---\n"
    end
    if w != '' then
      warn << w
      warn << env << "\n\n"
    end
  end

  labels.each_key {|key|
    # \figref と \tabref がラベル名に content: や tab: を付け加えている．
    k = key.gsub(/^(content|tab):/, '')
    if /\\(content|tab)?ref\{(#{key}|#{k})\}/ !~ s then
      warn << "図表{#{key}}は本文から参照されていない(?)\n"
    elsif /\\label\{#{key}\}/ =~ $` then
      warn << "図表{#{key}}は本文から参照される前に登場している(?)\n"
    end
  }
  if warn != '' then
    add_filename!(warn, filename)
    print "=== 図表 ===\n" + warn + "\n"
  end
end

def check_file(filename, printFilename)
  # reset variables...
  $zpline = ''
  $zkline = ''
  $zkuten = 0
  $zperiod = 0
  $regexp_p.each {|ent| ent['match'] = ''}
  $regexp_s.each {|ent| ent['match'] = ''}
  # read the entire file
  begin
    file = File.open(filename)
    texts = file.read
    file.close()
  rescue => e
    p e.message
    abort
  end
  # convert to UTF-8, LF line break
  texts = NKF.nkf('-w -Lu', texts)

  texts = prepare(texts)
  paras = split_to_paras(texts)

  puts "\n[checking paragraphs]" if $debug
  paras.each.with_index(1) {|par, index|
    if $debug then
      par.sentences.each {|s| print "P#{index}|#{s}\n"}
    end
    par.check_paragraph()
    par.sentences.each {|s| s.check_sentence()}
  }
  puts "\n--------------------------------\n" if $debug

  fname = printFilename ? filename : nil
  print_regexp_check_results(fname)
  print_kutouten_check_results(fname)
  check_figure_and_table(texts, fname)
end

def main
  params = ARGV.getopts('dmh')
  $debug = params["d"]
  $mono = params["m"]
  $help = params["h"]
  $name = $0.gsub(/.*\//, '')

  if $help || ARGV.length == 0 then
    puts <<~EOS
      Usage: ruby #{$name} [-m][-h][-d] files...
      日本語のLaTeXのファイルに対して(いいかげんな)警告を出力します．
      オプション:
        -m: ANSI colorを使わない
        -h: ヘルプ (この画面)
        -d: デバッグ用
      例:
        ruby #{$name} foo.tex bar.tex
    EOS
    exit(1)
  end

  print "=====================================================\n"
  print " 間違った指摘をする可能性が十分あるので注意すること!\n"
  print " checked by #{$name} #{$VERSION}\n"
  print "=====================================================\n\n"

  nfiles = ARGV.length
  while file = ARGV.shift do
    print "checking #{file} ...\n\n"
    check_file(file, nfiles > 1)
  end
end

main()

# EOF
