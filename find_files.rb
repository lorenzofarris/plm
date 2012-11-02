#!/usr/bin/ruby

require 'db'
require 'find'
require 'mp3info'
require 'sequel'
require 'sinatra/base'
require 'haml'
require 'Nokogiri'
require 'logger'
#require 'm3uzi'
#require 'id3'

LOG=Logger.new('mm.log')
LOG.level = Logger::DEBUG

def hashify node
  kids = node.element_children
  hm={}
  while key=kids.shift
    unless key.name=="key"
      #log.debug "I expected 'key' and I found #{key.name}"
      return nil
    end
    k=key.content
    value=kids.shift
    if value.name=="dict"
      v=hashify(value)
    elsif value.name=="array"
      a=v.element_children
      aa=[]
      a.each do |e|
        aa << hashify(e)
      end
      v=aa
    else
      v=value.content
    end
    hm[k]=v
  end
  hm
end

def snarf_itunes_db
  xml=Nokogiri::XML(File.open("/Users/farrisl/Music/iTunes/iTunes Music Library.xml"))
  tracks_dict=xml.at_css "dict dict"
  tracks=tracks_dict.css "dict"
  tracks.each do |trak|
    t=hashify trak
    track=Itune.new
    track.artist = t['Artist'] if t.key? 'Artist'
    track.title = t['Name'] if t.key? 'Name'
    track.genre = t['Genre'] if t.key? 'Genre'
    track.rating = t['Rating'] if t.key? 'Rating'
    track.bpm = t['BPM'] if t.key? 'BPM'
    track.album = t['Album'] if t.key? 'Album'
    track.save
  end
end

def build_weights_table
  # speed goes from 1 for slow to 3 for fast
  # styles are 1:ballroom, 2:latin, 3:club
  # I need a method when no dance would get chosen
  weights = [ {:dance=>'Waltz',               :speed=>1, :style=>1, :weight=>3, :interval=>7},
              {:dance=>'Tango',               :speed=>1, :style=>1, :weight=>3, :interval=>8},
              {:dance=>'Viennese Waltz',      :speed=>3, :style=>1, :weight=>2, :interval=>12},
              {:dance=>'Foxtrot',             :speed=>1, :style=>1, :weight=>3, :interval=>7},
              {:dance=>'Quickstep',           :speed=>3, :style=>1, :weight=>2, :interval=>8},
              {:dance=>'Cha Cha',             :speed=>2, :style=>2, :weight=>3, :interval=>7},
              {:dance=>'Rumba',               :speed=>1, :style=>2, :weight=>3, :interval=>7},
              {:dance=>'Samba',               :speed=>3, :style=>2, :weight=>2, :interval=>12},
              {:dance=>'Jive',                :speed=>3, :style=>2, :weight=>2, :interval=>16},
              {:dance=>'Paso Doble',          :speed=>1, :style=>2, :weight=>1, :interval=>32},
              {:dance=>'Bolero',              :speed=>1, :style=>2, :weight=>1, :interval=>24},
              {:dance=>'3x Swing',            :speed=>2, :style=>2, :weight=>2, :interval=>16},
              {:dance=>'WC Swing',            :speed=>1, :style=>3, :weight=>3, :interval=>8},
              {:dance=>'Night Club Two Step', :speed=>1, :style=>3, :weight=>3, :interval=>8},
              {:dance=>'Salsa',               :speed=>3, :style=>3, :weight=>3, :interval=>8},
              {:dance=>'Hustle',              :speed=>3, :style=>3, :weight=>1, :interval=>18} 
    ]

  weights.each do |w|
    weight=Weight.new
    weight.dance=w[:dance]
    weight.speed=w[:speed]
    weight.style=w[:style]
    weight.weight=w[:weight]
    weight.interval=w[:interval]
    weight.last=0
    weight.save
  end
end

def song_to_s(song)
  "Title=#{song[:title]}; Artist=#{song[:artist]}; Dance=#{song[:dance]}; Rating=#{song[:rating]}"
end

def find_files
  Find.find("/Users/farrisl/Music/rainier-dance") do |f|
    if f.match(/\.mp3\Z/i)
      Mp3Info.open(f) do |mp3info|
        s=Song.new()
        s.title=nil
        s.title=mp3info.tag.title
        #puts s.title
        s.artist=nil
        s.artist=mp3info.tag.artist
        #puts s.artist
        s.dance=nil
        s.dance=mp3info.tag2.TCON
        #puts "Dance: #{s.dance}"
        s.uid=nil
        id=mp3info.tag2.UFID
        unless id=~/^[0-9a-fA-F]+$/ 
          t=Time.now
          id=format("%X", ((t.to_i * 1000000)+t.usec))
        end
        s.uid=id
        #puts "ID: #{s.uid}"
        s.rating=nil
        s.rating=mp3info.tag2.POPM.to_i unless mp3info.tag2.POPM.nil?
        #puts "Rating: #{s.rating}"
        s.bpm=nil
        s.bpm=mp3info.tag2.TBPM.to_i unless mp3info.tag2.TBPM.nil?
        #puts "BPM: #{s.bpm}"
        s.path=f
        s.album=nil
        s.album=mp3info.tag.album
        s.length=mp3info.length
        s.save
      end
#      t=ID3::Tag2.new
#      t.read(f)
#      puts t
    end
  end   
end

def dump_db
  Song.all do |s|
    puts format("Title: %s; Path: %s, ID: %s, Dance: %s", s.title, s.path, s.uid, s.dance)   
  end
end

# changing in consideration of song being
# already changed before passing in 
#def change_file_metadata(song, params)
def change_file_metadata(song,)
  Mp3Info.open(song[:path]) do |mp3|
    #song.dance=params['genre']
    mp3.tag2.TCON=song.dance
    #song.title=params['title']
    mp3.tag.title=song.title
    #song.artist=params['artist']
    mp3.tag.artist=song.artist
    #song.rating=params['rating'].to_i
    mp3.tag2.POPM=song.rating
    #song.save
  end
end

def set_itunes_rating_in_file
  Song.all.each do |s|
    tunes=DB[:itunes].where(:title=>s.title, :artist=>s.artist, :album=>s.album)
    LOG.info("found #{tunes.count} matches for #{s.title} by #{s.artist}") if tunes.count > 1
    if tunes.count > 0
      #LOG.debug "#{tunes.count} match"
      tune=tunes.first
      #LOG.debug "tune: #{tune}"
      unless tune[:rating].nil?
        rating=tune[:rating].to_i
        if rating > 0
          s.rating=rating
        end
      end
      unless tune[:bpm].nil?
        bpm=tune[:bpm].to_i
          s.bpm=bpm
      end
      s.save
    end     
  end
end

def add_genres
  Song.all.each do |s|
    w=Weight[:dance=>s.dance]
    if w.nil?
      w=Weight.new
      w.dance=s.dance
      w.save
    end
  end
end

