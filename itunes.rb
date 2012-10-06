require 'sequel'
require 'sinatra'
require 'nokogiri'
require 'logger'

log=Logger.new("itunes.log")
log.level=Logger::DEBUG

DB=Sequel.sqlite("itunes.db")

DB.create_table :tracks do
  primary_key :id
  String :title
  String :artist
  String :genre
  String :bpm
  String :rating 
  String :album
end

class Track < Sequel::Model
end

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

xml=Nokogiri::XML(File.open("iTunes Music Library.xml"))
tracks_dict=xml.at_css "dict dict"
tracks=tracks_dict.css "dict"
tracks.each do |trak|
  t=hashify trak
  track=Track.new
  track.artist = t['Artist'] if t.key? 'Artist'
  track.title = t['Name'] if t.key? 'Name'
  track.genre = t['Genre'] if t.key? 'Genre'
  track.rating = t['Rating'] if t.key? 'Rating'
  track.bpm = t['BPM'] if t.key? 'BPM'
  track.album = t['Album'] if t.key? 'Album'
  track.save
end
