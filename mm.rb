#!/usr/bin/ruby

require 'db'
require 'mp3info'
require 'sequel'
require 'sinatra/base'
require 'haml'
require 'Nokogiri'
require 'logger'

LOG=Logger.new('mm.log')
LOG.level = Logger::DEBUG



def make_buckets(idx, speed, style)
  buckets=[]
  #LOG.debug "make_buckets: Index: #{idx}, Speed: #{speed}, Style: #{style}"
  Weight.where(:interval > 0).all.each do |w|
    #LOG.debug "make_buckets: Dance: #{w.dance}; Speed: #{w.speed}; Style: #{w.style}; Last Play: #{w.last}"
    unless w.speed==speed || w.style==style
      if w.last==0 || (idx - w.last)> w.interval
        #LOG.debug "make_buckets: Dance: #{w.dance} added to buckets"
        buckets << w
      end
    end
  end

  LOG.debug "returning #{buckets.size} buckets"
  buckets
end

def render_song_list(html, songs)
  #LOG.debug html
  doc=Nokogiri::HTML::DocumentFragment.parse(html)
  first=true
  row=doc.at_css("tr.song")
  trow=row.dup
  #LOG.debug(row.to_html)
  last_row=row
  songs.each  do |song|
    # already have first row in the template for layout purposes
    unless first
      last_row=row
      row=trow.dup
      last_row.add_next_sibling(row)
    else
      first=false
    end
    LOG.debug song.to_s
    title=row.at_css("input[name='title']")
    #LOG.debug title.to_html
    title['value']= "#{song[:title]}"
    #LOG.debug title.to_html
    #LOG.debug row.to_html
    row.at_css("input[name='artist']")['value']=song[:artist] ? "#{song[:artist]}" : ""
    row.at_css("input[name='genre']")['value']=song[:dance] ? "#{song[:dance]}" : ""
    unless song[:rating].nil? || song[:rating]==0
      rating = "#{song[:rating]}"
      #LOG.debug "Rating=#{rating}"
    else 
      rating="0"
    end   
    select=row.at_css("select[name='rating'] option[value='#{rating}']")
    select['selected']="true" unless select.nil?
    row.at_css("input[name='uid']")['value']=song[:uid] ? "#{song[:uid]}" : ""
    row.at_css("input[name='path']")['value']=song[:path]
  end
  doc.to_html
end

def render_dance_list(html)
  #LOG.debug html
  doc=Nokogiri::HTML::DocumentFragment.parse(html)
  first=true
  row=doc.at_css("tr.dance")
  last_row=row
  row_template=row.dup
  
  Weight.order(:dance).all.each do |w|
    LOG.debug "dance is #{w.dance}, style is #{w.style}, speed is #{w.speed}"
    # already have first row in the template for layout purposes
    unless first
      last_row=row
      row=row_template.dup
      last_row.add_next_sibling(row)
    else
      first=false
    end
    dance=row.at_css("input[name='dance']")
    dance['value']= "#{w.dance}"
    speed=row.at_css("select[name='speed'] option[value='#{w.speed}']")
    unless speed.nil?
      speed['selected']="true"
    end
    style=row.at_css("select[name='style'] option[value='#{w.style}']")
    unless style.nil?
      style['selected']="true"
    end
    row.at_css("input[name='id']")['value']="#{w.id}"
    interval=row.at_css("input[name='interval']")
    unless (interval.nil? || w.interval.nil?)
      interval['value']="#{w.interval}"         
    else
      interval['value']="0"
    end
    list_link=row.at_css "a"
    list_link['href']="list?dance=#{w.dance}"
  end
  doc.to_html
end

def how_many_of_each(songs)
  dances={}
  songs.each do |s|
    unless dances.key?(s.dance) 
      dances[s.dance]=0
    end
    dances[s.dance]+=1
  end
  dances
end

def make_a_dancelist(s=60)
  # create a randomized list of dances, according to interval
  # rules defined in the DB
  i=0
  songs=[]
  # reset the last play of each dance type to 0
  Weight.all.each do |w|
    w.last=0
    w.save
  end
  songs << Weight[:dance=>'Waltz']
  until i>= s
    #LOG.debug "make_a_playlist: i=#{i}"
    #LOG.debug "make_a_playlist: songs[i] = #{songs[i].dance}"
    # don't have two fast dances back to back
    speed = (songs[i].speed==3) ? 3 : 0
    buckets = make_buckets(i, speed, songs[i][:style])
    # if I can't find an eligible dance, remove the requirements on style
    if buckets.length==0
      buckets = make_buckets(i, speed, 0)
      if buckets.length==0
        buckets = make_buckets(i, 0, 0)
      end
    end
    song_idx = (rand() * (buckets.length - 1)).round
    LOG.debug "#{song_idx} out of #{buckets.length}"
    song=buckets[song_idx]
    LOG.debug "make_a_dancelist: chose #{song.dance}"
    i+=1
    song.last=i
    song.save
    songs << song
  end
  songs
end

# generate a playlist
# use make_a_dancelist to choose the dances
# use additional criteria passed in a hash to further restrict song selection
# currently will support only the additional criteria of rating and length
def new_playlist(m={})
  number=60
  max_length=0
  min_rating=0
  max_rating=0
  min_length=0
  max_length = m[:length] if m.key?(:length)
  number=m[:number] if m.key?(:number)
  dances=make_a_dancelist(number)
  songs = []
  dances.each do |d|
    la = Song.where(:dance=>d.dance)
    if max_length > 0
      lb = la.where{:length < max_length}
      la=lb
    end
    if min_rating > 0
      lb = la.where{:rating >= min_rating}
      la=lb
    end
    lm = la.map(:uid)
    idx = (rand() * (lm.length - 1)).round
    songs.each do |uid|
      if lm[idx] == uid
        i = idx + 1
        idx = i % lm.length
      end
    end
    songs << Song[:uid=>lm[idx]]
  end
  songs.each do |s|
    #LOG.debug "#{s.dance} #{s.title}"
  end
  songs 
end


class MMApp < Sinatra::Base
  set :logging,true
  set :sessions,true
  set :method_override, true
  set :inline_templates, true
  set :static, true
  set :haml, :format => :html5
  
  get '/' do
    haml :index
  end
  
  get '/list' do
    @songs=nil
    @title = "Music Manager"
    #LOG.debug "#{params}"
    #LOG.debug "#{params.key?('dance')}"
    if params.key?('dance')
      LOG.debug "dance = #{params['dance']}"
      @songs=Song.where(:dance=>"#{params['dance']}").all
      #LOG.debug "#{@songs.count} matching songs"
      @message= "#{params['dance']} songs"
    else
      @message = "All Songs"
      @songs = Song.order(:dance).all
      #LOG.debug "#{@songs.count} matching songs"
    end
    render_song_list(haml(:list),@songs)
  end
  
  get '/search' do
    term=params['term']
    LOG.debug("term=#{term}")
    if term
      s = Song.where(Sequel.join([:artist, :title, :album, :path]).ilike("%#{term}%"))
      LOG.debug "#{s.sql}"
      @songs=s.all
    else
      @songs = Song.order(:dance).all
    end
    render_song_list(haml(:list),@songs)
  end
  
  post '/modify' do
    song=Song[:uid=>params['uid']]
    change_file_metadata(song, params)
    #@songs = Song.order(:dance).all    
    render_dance_list(haml(:dances))
  end
  
  post '/change_weight' do
    if params.key?('id') 
      w=Weight[params['id'].to_i]
      w.style=params['style'].to_i
      w.speed=params['speed'].to_i 
      w.interval=params['interval'].to_i
      w.save
    end
    render_dance_list(haml(:dances))
  end
  
  get '/dances' do
    render_dance_list(haml(:dances))
  end
  
  get '/playlist' do
    doc=Nokogiri::HTML::Document.parse(haml(:playlists))
    row=doc.at_css "tr.playlist"
    trow=row.dup 
    first=true
    playlists = Playlist.all
    playlists.each do |pl| 
      unless first
        last_row = row
        row = trow.dup()
        last_row.add_next_sibling(row)
      else
        first = false
      end
      name = row.at_css("td.name")
      name.content = pl.name
    end
  end
  
  get '/playlist/new' do
    # generate a new random playlist
    songs = new_playlist
    # create a unique name for the playlist
    now=Time.now
    nows=now.strftime("%y%m%d%H%M%S")
    name="pl_#{nows}"
    # create the playlist in the database
    playlist=Playlist.new()
    playlist.name=name
    playlist.save
    ordinal=10
    f=File.new("#{name}.m3u", "w")
    songs.each do |s|
        item=Plsong.new
        item.order = ordinal
        item.song_id = s.id
        item.save
        ordinal = ordinal + 10
        f.puts s.path
    end
    f.close
    render_song_list(haml(:list),songs)
  end
  
  get '/dancelist' do
    dances=make_a_dancelist(60)
    doc=Nokogiri::HTML::Document.parse(haml(:dancelist))
    ol=doc.at_css "ol"
    dances.each do |d|
      li=Nokogiri::XML::Node.new "li", doc
      ol.add_child(li)
      li.content=d.dance
    end
    table=doc.at_css "table"
    tr=Nokogiri::XML::Node.new "tr",doc
    td1=Nokogiri::XML::Node.new "td",doc
    td2=Nokogiri::XML::Node.new "td",doc
    td1['class']="dance"
    td2['class']="total"
    tr.add_child(td1)
    tr.add_child(td2)
    totals=how_many_of_each(dances)
    totals.each do |d, t|
      tr1=tr.dup()
      table.add_child(tr1)
      tr1.at_css("td.dance").content=d
      tr1.at_css("td.total").content=t
    end
    doc.to_html
  end
end


#find_files
#snarf_itunes_db
#set_itunes_rating_in_file

#MMApp.run!

__END__

@@ layout
%html
  %head
    %title #{@title}
  %body
    %div#main_content 
      = yield
    %div#footer
      %a{:href => url("/")} Return to Main Page
 

@@ dances
The interval is the minimum number of other dances that get played before a dance gets played again.
%table
  %tr.heading
    %th Dance
    %th Speed
    %th Style
    %th Interval
    %th 
    %th
  %tr.dance
    %form{:action=>"/change_weight", :method=>"post"}
      %td
        %input{:name=>'dance'}
        %input{:name=>'id', :type=>'hidden'}
      %td
        %select{:name=>'speed'}
          %option{:value=>1} Slow
          %option{:value=>2} Medium
          %option{:value=>3} Fast
      %td
        %select{:name=>'style'}
          %option{:value=>1} Ballroom
          %option{:value=>2} Latin/Rhythm
          %option{:value=>3} Club
          %option{:value=>4} Other
      %td
        %input{:name=>'interval'}
      %td
        %button{:type=>'submit'} Change It!    
      %td
        %a{:href=>"list/genre"} List Songs    

          
@@index
%ul
  %li
    %a{:href=>url("dances")} List Dances
  %li
    %form{:action=>url("search"), :method=>"get"}
      %input{:name=>'term', :size=>'60'}
      %button{:type=>'submit'} Search
  %li 
    %a{:href=> url('playlist')} Make a playlist
 
@@playlists
%table
  %tr.heading
    %td Name
  %tr.playlist
    %td.name &nbsp;  
    
@@dancelist
%table
%ol
            
@@list
#message #{@message}
#songs
  %table
    %tr.song
      %form{:action=>"/modify", :method=>"post"}
        %td 
          %input{:name=>'uid', :type=>'hidden'}
          %input{:name=>'title', :size=>"50"}
        %td
          %input{:name=>'artist', :size=>"30"}
        %td
          %input{:name=>'genre', :size=>"20"}
        %td
          %select{:name=>'rating'}
            %option{:value=>'20'}20
            %option{:value=>'40'}40
            %option{:value=>'60'}60
            %option{:value=>'80'}80
            %option{:value=>'100'}100
        %td
          %button{:type=>'submit', :name=>'submit'} Change It!
        %td
          %input{:name=>'path', :size=>"50"}
           
            
@@playlist
#name #{@name}
#songs
  %table
    %tr.song
      %td.title
      %td.artist
      %td.genre
      %td.order       