require 'sequel'

DB=Sequel.sqlite('songs.db')

unless DB.table_exists?(:songs)
  DB.create_table :songs do 
    primary_key :id
    String :uid, :index=>true, :unique=>true
    String :title
    String :artist
    String :dance
    String :path
    String :album
    Integer :rating
    Integer :bpm
    Float :length
  end
end

unless DB.table_exists?(:weights)
  DB.create_table :weights do
    primary_key :id
    String :dance, :index=>true, :unique=>true
    Integer :speed
    Integer :style
    Integer :weight
    Integer :interval
    Integer :last
  end
end

unless DB.table_exists?(:itunes)
  DB.create_table :itunes do
    primary_key :id
    String :title
    String :artist
    String :genre
    String :bpm
    String :rating 
    String :album
  end
end

unless DB.table_exists?(:playlists)
  DB.create_table :playlists do
    primary_key :id
    String :name
  end
end

unless DB.table_exists?(:plsongs)
  DB.create_table :plsongs do
    primary_key :id
    foreign_key :playlist_id, :playlists
    foreign_key :song_id, :songs
    Integer :order
  end
end

class Itune < Sequel::Model
end

class Weight < Sequel::Model
end  
  
class Song < Sequel::Model
end

class Playlist < Sequel::Model
  one_to_many :plsongs
end

class Plsong < Sequel::Model
  many_to_one :playlist
  one_to_one :song
end

