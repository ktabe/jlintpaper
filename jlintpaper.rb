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
# Copyright 2016 (C) Kota Abe
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

$VERSION = '0.2.3'

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

# rubyの正規表現メモ:
# (?=pat) 肯定先読み(positive lookahead)
# (?!pat) 否定先読み(negative lookahead)
# (?<=pat) 肯定後読み(positive lookbehind)
# (?<!pat) 否定後読み(negative lookbehind)

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

# 段落に対するチェック
$regexpPara = [
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
$regexp = [
  # 表記
  {'regexp'=>/[０-９Ａ-Ｚａ-ｚ]/, 'desc'=>'全角英数字は使わない'},
  {'regexp'=>/[^\\],[^\d\s'"]/, 'desc'=>',の後に空白がない'},
  {'regexp'=>/（\p{ascii}*）/, 'desc'=>'全角括弧内が半角文字のみ(半角括弧にする?)'},
  {'regexp'=>/(?<!\s|。|．|\.|}|\)|）|\\hline)\s*$/, 'desc'=>'文末に句点やピリオドがない(?)'},
  #      {'regexp'=>/[^ \t}\.．。][ \t]*$/, 'desc'=>'文末が句点やピリオドで終わっていない'},
  #      {'regexp'=>/[，、][ \t]*$/, 'desc'=>'文末がカンマや読点で終わっている'},
  {'regexp'=>/^[ \t][，、]/, 'desc'=>'文頭がカンマや読点から始まっている'},
  {'regexp'=>/(?<=\p{^ascii})[ \t]+(?=\p{^ascii})/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=[．。、，])[ \t]+(?=\p{ascii})/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=\p{ascii})[ \t]+(?=[．。、，])/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=\p{^ascii})[.,]/, 'desc'=>'日本語文字のあとに半角カンマやピリオド（原則全角）'},
  {'regexp'=>/[“”"]/, 'desc'=>'ダブルクォーテーション(LaTeXでは ``と\'\' を使う．プログラムリストなどでは"はOK)'},
  # 相互参照
  {'regexp'=>/(^|[^図表\s])\s*\\ref\{[^}]*\}(?![節章項])/, 'desc'=>'\\refの前後に図・表あるいは章・節・項がない'},
  {'regexp'=>/[.\d]+[章節項]|[図表]\d+/, 'desc'=>'章や節，図表番号を直接指定している?(\\refを使うべき)'},
  {'regexp'=>/[.\d]+で(前|後)?述/, 'desc'=>'章や節番号を直接記述している?(「\\ref{..}章」のように書くべき)'},
  # 漢字とひらがな
  {'regexp'=>/(?<=\p{^Han}|)[#{nokanji}](?=\p{^Han})/,
   'desc'=>"原則として平仮名で表記すべき語句(#{nokanji} #{ieiceURL}"},
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
  {'regexp'=>/(全て|の時[^点間計]|の通り|有る|在る|居る|成る|出来|て上げる|て行く|て置く|て来る|て仕舞う|て見る|無い|\p{^Han}様\p{Hiragana}|\p{^Han}位{^Han}|丈|程[^度]|以って|且つ|但し|但(?=書)|従って|因る|(?<!その)他[^の\p{Han}\p{Katakana}]|(?<![の\p{Han}])外[^\p{Han}れ])/,
   'desc'=>"原則として平仮名で表記すべき語句(全て，出来，無い，時，通り，など) #{ieiceURL}"},
  {'regexp'=>/(?<=[^カ\p{Han}])所(?=\p{^Han})/,
   # ところ（現在のところ差し支えない）
   'desc'=>"原則として平仮名で表記すべき語句(所) #{ieiceURL}"},
  # 等（ら）→ら
  {'regexp'=>/(?<=[^均同冪平対])等(?=[^し\p{Han}])/, 'desc'=>'原則として平仮名で表記すべき語句(等)'},
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
  {'regexp'=>/そして/, 'desc'=>'原則として避けるべき語句（そして）'},
  {'regexp'=>/(なので|だから)/, 'desc'=>'口語表現「なので」「だから」→「であるため」'},
  {'regexp'=>/いけない/, 'desc'=>'口語表現（いけない）'},
  {'regexp'=>/(?<!して)から[,，、]/, 'desc'=>'口語表現 「から」（理由を表す場合）→「ため」'},
  {'regexp'=>/(です|ます|でしょう)[.．。が]/, 'desc'=>'「です・ます」調は使わない．「だ・である」調を使う（謝辞の中は良い）．'},
  {'regexp'=>/いい/, 'desc'=>'口語表現「いい」→「よい」'},
  {'regexp'=>/けど/, 'desc'=>'口語表現「けど」→「が」'},
  {'regexp'=>/っ?たら/, 'desc'=>'口語表現「たら」→「ると」「れば」「る場合」「た場合」など'},
  {'regexp'=>/いろんな/, 'desc'=>'口語表現「いろんな」→「様々な」'},
  {'regexp'=>/((?<=が)い|要)(ら|り|る)/, 'desc'=>'口語表現「いる」→「必要とする」'},
  {'regexp'=>/をする/, 'desc'=>'「をする」→「する」or「を行う」(?)'},
  {'regexp'=>/をして/, 'desc'=>'「をして」→「して」or「を行なって」(?)'},
  {'regexp'=>/することができ(る|ない)/, 'desc'=>'「することができる」「することができない」→「できる」「できない」(?)'},
  {'regexp'=>/することが可能/, 'desc'=>'「することが可能」→「できる」(?)'},
  {'regexp'=>/なので/, 'desc'=>'「なので」→「であるため」or「ので」(?)'},
  {'regexp'=>/\d{4,}[^年]/, 'desc'=>'大きな数字には3桁ごとにカンマを入れる(?)'},
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
  # 文
  {'regexp'=>/(\p{Han}|\p{Katakana}|[A-Za-z0-9])[.．。]$/, 'desc'=>'体言止め(?)'},
  {'regexp'=>/(?<![うくすつぶむるいた）)}])[.．。]$/, 'desc'=>'文の終わり方がおかしい(?)'},
  {'regexp'=>/[^\P{Hiragana}かがたはばやらいきしちにびみりくつすずえけげせてでへべめれおもとどのろを][，、]/, 'desc'=>'読点の前がおかしい(?)'},
  {'regexp'=>/は[，、].*はある[．。]$/, 'desc'=>'〜は，〜はある'},
  # 以下は問題ない場合も多い
  {'regexp'=>/(\p{Han}\p{Han})する[^，、]*\1/, 'desc'=>'「検索するために検索」のように同じサ変動詞が2回現れている(?)'},
  # {'regexp'=>/を行う/, 'desc'=>'を行う→する(?)'},
  {'regexp'=>/で[，、].*で[，、]/, 'desc'=>'「で，」が連続'},
  {'regexp'=>/(?<![にで])は[，、].*(?<![にで])は[，、]/, 'desc'=>'「は，」が連続'},
  {'regexp'=>/[^いる]が[，、].*[^いる]が[，、]/, 'desc'=>'「が，」が連続'},
  {'regexp'=>/際に.*際に/, 'desc'=>'「際に」が連続'},
  {'regexp'=>/場合.*場合/, 'desc'=>'「場合」が連続'},
  {'regexp'=>/対し.*対し/, 'desc'=>'「対し」が連続'},
  {'regexp'=>/ため.*ため/, 'desc'=>'「ため」が連続'},
  # 「対し」だけ例外扱い
  {'regexp'=>/(?<!対)([いきしちにひみり])[，、].*\1[，、]/, 'desc'=>'「〜し，〜し，」のように同じ「い段」の文字が読点の前で連続'},
  # 数式モードの中で連続する2文字以上の単語にマッチ
  # \Gは$~$が1行に複数あった場合への対策
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b[A-Za-z]{2,}[^$]*\$/, 'desc'=>'$log$のように書いた場合，l*o*gという意味．関数ならば\log，イタリックならば\textit{abc}を使うこと'},
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b,[0-9]{3}\b[^$]*\$/, 'desc'=>'数式モードの中で大きな数の桁区切りは{,}を使う'},
  # 中国人留学生の典型的な間違い
  # ここでは「ないの」は除外し，次でチェック
  {'regexp'=>/(?<!互|くら|ぐら|な)いの(?!だが)/, 'desc'=>'形容詞の後に余分な「の」(?)'}, ## 等しいのため
  # 「ないので」はOK
  {'regexp'=>/(?<=ない)の(?!で)/, 'desc'=>'「ないの」→「ない」(?)'}, ## 少ないの場合
  {'regexp'=>/(?<=い)だ(?=と)/, 'desc'=>'形容詞の後に余分な「だ」(?)'},  ## 少ないだと
#  {'regexp'=>/(?<=る)の(?!\p{Hiragana})/, 'desc'=>'余分な「の」(?)'},   ## いるの場合
  {'regexp'=>/(?<=る)の(?![かにはで])/, 'desc'=>'余分な「の」(?)'},   ## いるの場合
]

$regexpPara.each {|ent|
  ent['match'] = ''
}
$regexp.each {|ent|
  ent['match'] = ''
}

# 強制的に入れる行番号部分にマッチする正規表現
$lineRegexp = '^\d+:'

def addlinenum(t, lnum)
  "#{lnum}:#{t}"
end

def getlinenum(t)
  x = t.gsub(/^(\d+):.*/, '\1')
  x.to_i
end

def removelinenum(t)
  t.gsub(/^(\d+):/, '')
end

# single paragraph
class Paragraph
  attr_reader :str
  attr_reader :sentences
  def initialize(str)
    @str = str
    to_sentences()
  end
  def to_s
    "#{@str}"
  end

  # 段落を1つ以上の文に分割する
  def to_sentences
    # print "paragraph[#{to_s()}]\n"
    @sentences = []
    lnum = -1
    lstart = lnum
    remain = ''
    @str.each_line {|l|
      lnum = getlinenum(l)
      l = removelinenum(l)
      # print "lnum=#{lnum}, lstart=#{lstart}, remain=#{remain}, l=[#{l}]\n"
      lstart = lnum if remain == '' || remain == "\n"
      if (l != "\n" || remain != '') then
        remain << l
      end
      while /.*?([．。?？])/m =~ remain do
        #print "remain[" + remain + "]"
        remain = $'
        remain = '' if remain == "\n"
        finish($&, lstart, lnum)
        lstart = lnum
      end
    }
    finish(remain, lstart, lnum)
  end

  def finish(s, lstart, lnum)
    # print "finish #{lstart}-#{lnum} [#{s}]\n"
    if (s == '') then
      return
    end
    # 日本語文字に続く改行を削除
    s.gsub!(/(?<=[\p{^ascii}])\n\s*/m, '')
    # 残った改行は空白に置換
    s.gsub!(/\n/, ' ')
    obj = Sentence.new(s, lstart, lnum)
    @sentences << obj
  end

  def check_paragraph
    lnum = getlinenum(@str)
    line = removelinenum(@str)
    $regexpPara.each {|c|
      if c['regexp'] =~ line then
        tmp = line.gsub(c['regexp'], '>>>\&<<<')
        tmp = addlinenum(tmp, lnum)
        c['match'] <<= tmp.gsub(/\n/, "\n") + "\n";
      end
    }
  end
end

# single sentence
class Sentence
  attr_reader :str
  attr_reader :line1
  attr_reader :line2
  def initialize(str, line1, line2)
    @str = str
    @line1 = line1
    @line2 = line2
  end

  def to_s
    lines + ': ' + @str
  end

  def lines
    if @line1 == @line2 then
      @line1.to_s
    else
      @line1.to_s + '..'  + @line2.to_s
    end
  end

  def check_sentence
    return if /^\\newcommand/ =~ @str
    return if /\A\s*\Z/ =~ @str

    $regexp.each {|c|
      if c['regexp'] =~ @str then
        tmp = @str.gsub(c['regexp'], '>>>\&<<<')
        c['match'] <<= lines + ": " + tmp.gsub(/\n/, '') + "\n"
      end
    }

    if /[．，]/ =~ @str then
      $zperiod += 1
      $zpline << to_s + (/\n\Z/ =~ str ? '' : "\n")
    end
    if /[。、]/ =~ @str then
      $zkuten += 1
      $zkline << to_s + (/\n\Z/ =~ str ? '' : "\n")
    end
  end
end

def prepare(texts)
  # 行番号を行頭に付与
  lnum = 1
  t = ''
  texts.each_line {|l|
    t << addlinenum(l, lnum)
    lnum = lnum + 1
  }

  # *? は最小量指定子
  # % 以降を削除
  t.gsub!(/#{$lineRegexp}%.*?$\n/m, '')
  t.gsub!(/(?<!\\)%.*?$/m, '')

  # \\TODO{...}を削除
  t.gsub!(/\\TODO{.*?}/m, '')

  # \begin{comment}〜\end{comment}を削除
  t.gsub!(/\\begin{comment}.*?\\end{comment}/m, '')
  # \begin{document}までを削除
  t.gsub!(/.*\\begin{document}/m, '')
  # \end{document}以降を削除
  t.gsub!(/\\end{document}.*/m, '')

  # \cite{}の内部をチェックしないようにマスク
  t.gsub!(/(?<=\\cite{)[^}]*(?=})/, 'CITEMASK')
  t
end

def to_paragraph(texts0)
  texts = texts0.clone

  # remove figure and table
  texts.gsub!(/\\begin{(figure|table)\*?}.*?\\end{(figure|table)\*?}/m) {|x| x.gsub(/^.*$/, '')}

  # add sentinel
  texts = texts + "\n#{addlinenum('', 99999)}\n" if (texts !~ /\n#{$lineRegexp}\n$/)

  paras = []
  p = ''
  texts.each_line {|l|
    # print "[l=#{l}]\n"
    lnum = getlinenum(l)
    # 段落の先頭に空行を足さない
    if (p != '' || l !~ /#{$lineRegexp}$/) then
      p << l
    end
    # print "[p=#{p}]\n"
    # 段落ごとに切り分ける
    if /(\n#{$lineRegexp}\n|\\item|\\(begin|end|(sub)*section\*?|vspace)\{.*?\}|\\paragraph|\\par\s|\\newpage|\\clear(double)?page)/m =~ p then
      tmp = $`
      # print "[tmp=#{tmp}]\n"
      p = $' || ''
      if (p !~ /^\s*$/) then
        p = addlinenum(p, lnum)
      end
      if (tmp !~ /^\A*\Z/m) then
        paras << Paragraph.new(tmp)
      end
    end
  }
  paras
end

def printRegexpCheck
  $regexpPara.each {|c|
    print "===" + c['desc'] + "===\n" + c['match'] + "\n" if c['match'] != ''
  }
  $regexp.each {|c|
    print "===" + c['desc'] + "===\n" + c['match'] + "\n" if c['match'] != ''
  }
end

def printKutoutenCheck
  if ($zkuten > 0 && $zperiod > 0) then
    print "===句読点（。、）と全角のコンマやピリオド（．，）を混ぜて使わないこと===\n"
    print "  # 全角ピリオドあるいはカンマを含む行数: #{$zperiod}\n"
    print "  # 句読点を含む行数: #{$zkuten}\n\n"
    if (0 < $zkuten && $zkuten <= $zperiod) then
      print "  ===句読点が使われている行===\n" + $zkline + "\n"
    end
    if (0 < $zperiod && $zperiod < $zkuten) then
      print "==全角ピリオドあるいはカンマが使われている行==\n" + $zpline + "\n"
    end
  end
end

# check figure and table environments
def checkFigTab(s)
  tmp = s
  labels = {}
  warn = ''
  while (/\\begin\{(figure|table)\*?\}(\[.*?\])?(.*?)\\end\{\1\*?\}/m =~ tmp) do
    env = $1
    fig = $3
    tmp = $'
    if /\\caption/ !~ fig then
      warn << "#{env}環境に\\captionがない\n"
      warn << fig + "\n"
    end
    if /\\ecaption\{([^}]*[^.])\}/ =~ fig then
      warn << "英語キャプション(ecaption)の最後はピリオドが必要 " + $1 + "\n";
    end
    if /\\label{(.*?)}/ !~ fig then
      warn << "#{env}環境に\\labelがない\n"
      warn << fig + "\n"
    else
      labels[$1] = true
    end
  end

  labels.each_key {|key|
    # \figref と \tabref がラベル名に fig: や tab: を付け加えている．
    k = key.gsub(/^(fig|tab):/, '')
    if /\\(fig|tab)?ref\{(#{key}|#{k})\}/ !~ s then
      warn << "図表{#{key}}は本文から参照されていないようです\n"
    elsif /\\label\{#{key}\}/ =~ $` then
      warn << "図表{#{key}}は本文から参照される前に登場しているかもしれません\n"
    end
  }
  print "===図表===\n" + warn + "\n" if warn != ''
end

def main
  params = ARGV.getopts('d')
  debug = params["d"]
  name = $0.gsub(/.*\//, '')

  print "=====================================================\n"
  print " 間違った指摘をする可能性が十分あるので注意すること!\n"
  print " checked by #{name} #{$VERSION}\n"
  print "=====================================================\n\n"

  $zpline = ''
  $zkline = ''
  $zkuten = 0
  $zperiod = 0

  # read entire file
  texts = ARGF.read
  texts = NKF.nkf('-w -Lu', texts)

  texts = prepare(texts)
  paras = to_paragraph(texts)

  pnum = 1
  paras.each {|p|
    if (debug) then
      print "Paragraph #{pnum}\n"
      p.sentences.each {|s| print ">> #{s}\n"}
    end
    p.check_paragraph()
    p.sentences.each {|s|
      s.check_sentence()
    }
    pnum = pnum + 1
  }
  print "--------------------------------\n\n" if (debug)

  printRegexpCheck()
  printKutoutenCheck()

# print texts

  checkFigTab(texts)
end

main()

# EOF
