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

$VERSION = '0.1.0'

# 原則として平仮名で表記する語句
# Http://www.ieice.org/jpn/shiori/pdf/furoku_e.pdf 参照
nokanji = '事又之為共訳故挙'

# チェック用の正規表現
$regexp = [
  # 表記
  {'regexp'=>/[０-９]/, 'desc'=>'全角数字は使わない'},
  {'regexp'=>/[Ａ-Ｚａ-ｚ]/, 'desc'=>'全角英文字は使わない'},
  {'regexp'=>/,[^\d\s]/, 'desc'=>',の後に空白がない'},
  {'regexp'=>/（\p{ascii}*）/, 'desc'=>'全角括弧内が半角文字のみ(半角括弧にする?)'},
  {'regexp'=>/(?<!\s|。|．|\.|}|\\hline|\\\\)\s*$/, 'desc'=>'文末に句点やピリオドがない(?)'},
  #      {'regexp'=>/[^ \t}\.．。][ \t]*$/, 'desc'=>'文末が句点やピリオドで終わっていない'},
  #      {'regexp'=>/[，、][ \t]*$/, 'desc'=>'文末がカンマや読点で終わっている'},
  {'regexp'=>/^[ \t][，、]/, 'desc'=>'文頭がカンマや読点から始まっている'},
  {'regexp'=>/(?<=\p{^ascii})[ \t](?=\p{^ascii})/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=[．。、，])[ \t](?=\p{ascii})/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=\p{ascii})[ \t](?=[．。、，])/, 'desc'=>'不要な半角スペース(?)'},
  {'regexp'=>/(?<=\p{^ascii})[.,]/, 'desc'=>'日本語文字のあとに半角カンマやピリオド（原則全角）'},
  {'regexp'=>/[“”"]/, 'desc'=>'ダブルクォーテーション(LaTeXでは ``と\'\' を使う．プログラムリストなどでは"はOK)'},
  # 相互参照
  {'regexp'=>/[^図表]\\ref\{[^}]*\}+[^節章項]/, 'desc'=>'\\refの前後に図・表あるいは章・節・項がない'},
  {'regexp'=>/[.\d]+[章節項]|[図表]\d+/, 'desc'=>'章や節，図表番号を直接指定している?(\\refを使うべき)'},
  {'regexp'=>/[.\d]+で(前|後)?述/, 'desc'=>'章や節番号を直接記述している?(「\\ref{..}章」のように書くべき)'},
  # 漢字とひらがな
  {'regexp'=>/(?<=\p{^Han})[#{nokanji}](?=\p{^Han}|(全て|出来|無い|の時[^点間]))/,
   'desc'=>"原則として平仮名で表記すべき語句(#{nokanji}，全て，出来，無い，時など) http://www.ieice.org/jpn/shiori/pdf/furoku_e.pdf"},
  {'regexp'=>/(?<=[^カ\p{Han}])所(?=\p{^Han})/,
   'desc'=>"原則として平仮名で表記すべき語句(所) http://www.ieice.org/jpn/shiori/pdf/furoku_e.pdf"},
  {'regexp'=>/(?<=[^均同冪平対])等(?=[^し\p{Han}])/, 'desc'=>'原則として平仮名で表記すべき語句(等)'},
  {'regexp'=>/[一二三四五六七八九]つ/, 'desc'=>'一つ，二つなどが数値を表す場合はアラビア数字を用いる(日本語の言い回しならばOK)'},
  {'regexp'=>/同士/, 'desc'=>'同士→どうし'},
  {'regexp'=>/わかる/, 'desc'=>'わかる→分かる'},
  {'regexp'=>/上で/, 'desc'=>'上で→うえで（「上で」を「うえで」と読む場合）'},
  {'regexp'=>/押さえ/, 'desc'=>'押さえ→おさえ'},
  {'regexp'=>/例え/, 'desc'=>'例え→たとえ'},
  {'regexp'=>/行な/, 'desc'=>'行な→行（「な」は送らない）'},
  {'regexp'=>/オーバー/, 'desc'=>'オーバー→オーバ'},
  {'regexp'=>/タイマー/, 'desc'=>'タイマー→タイマ'},
  {'regexp'=>/インターフェイス/, 'desc'=>'インターフェイス→インタフェース'},
  # 表現
  {'regexp'=>/そして/, 'desc'=>'原則として避けるべき語句（そして）'},
  {'regexp'=>/(なので|だから)/, 'desc'=>'口語表現「なので」「だから」→「であるため」'},
  {'regexp'=>/いけない/, 'desc'=>'口語表現（いけない）'},
  {'regexp'=>/から[,，、]/, 'desc'=>'口語表現 「から」（理由を表す場合）→「ため」'},
  {'regexp'=>/(です|ます|でしょう)[.．。]/, 'desc'=>'「です・ます」調は使わない．「だ・である」調を使う（謝辞の中は良い）．'},
  {'regexp'=>/いい/, 'desc'=>'口語表現「いい」→「よい」'},
  {'regexp'=>/けど/, 'desc'=>'口語表現「けど」→「が」'},
  {'regexp'=>/っ?たら/, 'desc'=>'口語表現「たら」→「ると」「れば」「る場合」「た場合」など'},
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
  {'regexp'=>/[^\p{Han}にてでがらをり]行う/, 'desc'=>'「行う」の前が変(?)'},
  {'regexp'=>/をは/, 'desc'=>'をは(書き間違い?)'},
  {'regexp'=>/しように/, 'desc'=>'しように(書き間違い?)'},
  # 以下は問題ない場合も多い
  {'regexp'=>/(\p{Han}\p{Han})する[^、。]*\1/, 'desc'=>'「検索するために検索」のように同じサ変動詞が2回現れている(?)'},
  #      {'regexp'=>/を行う/, 'desc'=>'を行う→する(?)'},
  {'regexp'=>/で[，、].*で[，、]/, 'desc'=>'「で，」が連続'},
  {'regexp'=>/(?<![にで])は[，、].*(?<![にで])は[，、]/, 'desc'=>'「は，」が連続'},
  {'regexp'=>/[^いる]が[，、].*[^いる]が[，、]/, 'desc'=>'「が，」が連続'},
  {'regexp'=>/際に.*際に/, 'desc'=>'「際に」が連続'},
  {'regexp'=>/場合.*場合/, 'desc'=>'「場合」が連続'},
  {'regexp'=>/対し.*対し/, 'desc'=>'「対し」が連続'},
  #      {'regexp'=>/は[，、](?!.*(である|できる|ある|持つ|いる|する|述べる|行う|示す)[．。]$)/, 'desc'=>'係り結び'},
  # 数式モードの中で連続する2文字以上の単語にマッチ
  # \Gは$~$が1行に複数あった場合への対策
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b[A-Za-z]{2,}[^$]*\$/, 'desc'=>'$log$のように書いた場合，l*o*gという意味．関数ならば\log，イタリックならば\textit{abc}を使うこと'},
  {'regexp'=>/\G[^$]*\$[^$]*(?<![\\{])\b,[0-9]{3}\b[^$]*\$/, 'desc'=>'数式モードの中で大きな数の桁区切りは{,}を使う'},
]

$regexp.each {|ent|
  ent['match'] = ''
}

#
# single sentence
#
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
end

#
# chop LaTeX source files into sentences
#
def chopTexts(texts)
  texts.gsub!(/\\COM\{(.*?)(?<!\\)\}/m) {|x| x.gsub(/^.*$/, '')}
  texts.gsub!(/\\TODO\{(.*?)(?<!\\)\}/m) {|x| x.gsub(/^.*$/, '')}

  sentences = []
  remain = ''
  lnum = 0                        # 現在の行番号
  lstart = 0                      # 文の開始行番号
  texts.each_line {|l|
    lnum = lnum + 1
    #print "#{lnum}: [#{l}]"
    lstart = lnum if remain == ''
    # %から改行までを削除
    remain << l.gsub(/(?<!\\)%.*$/m, '')
    # print "#{lnum}: [#{l}] [#{tmp}]\n"

    # 文ごとに切り分ける
    while /.*?([．。]|\n\n|\\\\|\\item|\\end\{)/m =~ remain do
      #print "remain[" + remain + "]"
      remain = $'
      str = $&;
      str.gsub!(/^\s+/, '')
      str.gsub!(/(\\item|\\end\{)/, '')
      # print 'str1[' + str + ']'
      # (?<=pat)は肯定後読み (?!=pat)は肯定先読み
      str.gsub!(/(?<=[\p{Han}\p{Hiragana}\p{Katakana}，．、。])\n(?=[\p{Han}\p{Hiragana}\p{Katakana}，．、。])/, '')
      # 残った改行は空白に置換
      str.gsub!(/\n/, ' ')
      #print 'str2[' + str + ']'

      next if /\A\s*\Z/ =~ str

      if /\\((sub)*section|paragraph)\{.*?\}/ =~ str then
        left = $`
        title = $&
        str = $'
        # print "left = [#{left}]\n"
        sentences << Sentence.new(left, lstart, lnum) if /\A\s*\Z/ !~ left
        # print "SECTION #{title}\n"
      end

      obj = Sentence.new(str, lstart, lnum)
      # print "str = [#{obj}]\n"
      sentences << obj
      lstart = lnum
    end
    #  lstart = lnum
  }
  sentences
end

# check texts
def checkTexts(sentences)
  skip = true
  lnum = -1
  $zpline = ''
  $zkline = ''
  $zkuten = 0
  $zperiod = 0

  sentences.each {|obj|
    line = obj.str

    # skip until \begin{document}
    skip = false if skip && /\\begin\{document\}/ =~ line
    # skip from \begin{comment} to \end{comment}
    skip = false if skip && /\\end\{comment\}/ =~ line
    skip = true if !skip && /\\begin\{comment\}/ =~ line
    next if skip
    #  next if /^%/ =~ line
    #  next if /^\\COM\{/ =~ line
    line.gsub!(/\\begin\{.*?\}(\[.*?\])?/, '')
    line.gsub!(/\\end\{.*?\}/, '')
    line.gsub!(/\\clearpage/, '')
    line.gsub!(/\\newpage/, '')
    line.gsub!(/\\item/, '')
    next if /^\\newcommand/ =~ line
    next if /\A\s*\Z/ =~ line

    if /[．，]/ =~ line then
      $zperiod += 1
      $zpline << obj.to_s + (/\n\Z/ =~ line ? '' : "\n")
    end
    if /[。、]/ =~ line then
      $zkuten += 1
      $zkline << obj.to_s + (/\n\Z/ =~ line ? '' : "\n")
    end

    $regexp.each {|c|
      if c['regexp'] =~ line then
        tmp = line.gsub(c['regexp'], '>>>\&<<<')
        c['match'] <<= obj.lines + ": " + tmp.gsub(/\n/, '') + "\n"
      end
    }
  }
  if skip then
    STDERR.print "\\begin{document}が見つかりませんでした!\n"
    exit 1
  end
end

def printRegexpCheck()
  $regexp.each {|c|
    print "===" + c['desc'] + "===\n" + c['match'] + "\n" if c['match'] != ''
  }
end

def printKutoutenCheck()
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
  tmp = ''
  lnum = 0
  s.each_line {|line|
    lnum = lnum + 1
    # delete comments
    line.gsub!(/%.*/, '')
    #  next if line == "\n"
    tmp << lnum.to_s + ": " + line
  }

  #
  # \labelの抽出
  #
  labels = {}
  warn = ''
  while (/\\begin\{(figure|table)\}\[.*?\](.*?)\\end\{\1\}/m =~ tmp) != nil do
    env = $1
    fig = $2
    tmp = $'
    if /\\caption/ !~ fig then
      warn << "#{env}環境に\\captionがない\n"
      warn << fig + "\n"
    end
    if /\\ecaption\{([^}]*[^.])\}/ =~ fig then
      warn << "英語のキャプション(ecaption)の最後はピリオドが必要 " + $1 + "\n";
      #    warn << fig + "\n"
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

# read entire file
texts = ARGF.read
texts = NKF.nkf('-w -Lu', texts)

print "=====================================================\n"
print " 間違った指摘をする可能性が十分あるので注意すること!\n"
print " checked by #{$0} #{$VERSION}\n"
print "=====================================================\n\n"

sentences = chopTexts(texts)
checkTexts(sentences)
printRegexpCheck()
printKutoutenCheck()
checkFigTab(texts)

# EOF
