#!/usr/bin/env ruby

require 'slack'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'time'

# Use a cookie written to filesystem if exists
def set_cookie
  if File.exist?('cookie.txt')
    puts 'Cookie exists'
    File.read('cookie.txt')
  else
    ''
  end
end

def yaml(file_path)
  YAML.load_file(file_path)
  rescue Exception => err
    $stederr.puts "YAML invalid: #{file_path}"
    raise "#{err}"
end

# Moving user-specific data to yaml
@config            = yaml('config.yaml')
@channel           = @config['channel']            || '#general'
@breakbase_game_id = @config['breakbase_game_id']
@interval          = @config['interval']           || 600
@reminder          = @config['reminder']           || 21600
@new_reminder      = @config['new_reminder']       || 3600
@token             = @config['token']
@quiet_hours       = @config['quiet_hours']        || ['21:00', '9:00']
@quiet_weekend     = @config['quiet_weekend']      || true
@tz                = @config['timezone']           || '-04:00'

#@breakbase_url     = "http://breakbase.com/#{@breakbase_game_id}"
@breakbase_url     = "http://legacy.breakbase.com/#{@breakbase_game_id}"
#@breakbase_enter   = "http://breakbase.com/room/#{@breakbase_game_id}/enter"
@breakbase_enter   = "http://legacy.breakbase.com/room/#{@breakbase_game_id}/enter"
@breakbase_cookie  = set_cookie
@game_hash         = {}
@current_player    = ''
@timer             = 0

def quiet_hours?
  ret = false
  now = Time.now.getlocal(@tz)
  if @quiet_weekend
    ret = (now.saturday? || now.sunday?) ? true : false
  end
  unless ret
    @quiet_hours.flatten.each_slice(2) do |hours|
      qstart = hours.first
      qend   = hours.last
      if Time.parse("#{qstart} #{@tz}") > Time.parse("#{qend} #{@tz}")
        if ( now > Time.parse("#{qstart} #{@tz}") && now < Time.parse("24:00 #{@tz}") ) || ( now > Time.parse("0:00 #{@tz}") && now < Time.parse("#{qend} #{@tz}") )
          ret = true
        end
      else
        if ( now > Time.parse("#{qstart} #{@tz}") && now < Time.parse("#{qend} #{@tz}") )
          ret = true
        end
      end
    end
  end
  ret
end

def current_player_id
  id = @game_hash['game']['turn']
  @game_hash['game']['players'][id]
end

def player_name(id)
  @game_hash['users'][id]['name']
end

def check_player(player)
  if player == @current_player
    return true
  else
    return false
  end
end

def check_new_game
  begin
    new = @game_hash['request']['type']
  rescue NoMethodError => e
    return false
  else
    return true if new == 'new_game'
  end
end

def last_move
  words_a  = @game_hash['game']['next_move']['words']
  score    = @game_hash['game']['next_move']['total_points']
  player_i = @game_hash['game']['next_move']['player']
  player   = player_name(@game_hash['game']['players'][player_i])
  return [player, words_a, score]
end

def get_cookie(set_cookie_string)
  set_cookie_string.split('; ')[0]
end

def write_cookie
 File.open('cookie.txt', 'w') { |file| file.write(@breakbase_cookie) }
end

def bbase_get(uri_str)
  uri           = URI(uri_str)
  req           = Net::HTTP::Get.new(uri_str)
  req['Cookie'] = @breakbase_cookie

  bb_res = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(req)
  end
end

def bbase_post(uri_str)
  uri               = URI(uri_str)
  req               = Net::HTTP::Post.new(uri_str)
  req['Cookie']     = @breakbase_cookie

  req.set_form_data({
    'anon' => 'Enter anonymously!'
  })

  bb_res = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(req)
  end
end

def parse_html(html)
  # Grab the JSON part and cut off the notes (not real JSON)
  cleanup1 = html.match(/RoomMgr\.create\((.*)\)/)[1]
  cleanup2 = cleanup1.split(',', 3)[2].gsub(/, \[{"msg":.*/, '')
  cleanup  = cleanup2.gsub(/, \[{"note":.*/, '')
  JSON.parse(cleanup)
end

def find_mention(player)
   if m = @config['mentions'][player]
     id = @uids.select { |u| u['name'] == m }.first['id']
     "<@#{id}>"
  else
    player
  end
end

def notify_chat(player, score=false)
  Slack.configure do |config|
    config.token = @token
  end

  client   = Slack::Client.new
  @uids  ||= client.users_list['members']
  text     = "It's #{find_mention(player)}'s turn on BreakBase: #{@breakbase_url}"

  message = {
    :channel  => @channel,
    :username => 'Breakbase',
    :icon_url => 'https://pbs.twimg.com/profile_images/1364067224/icon.jpg',
    :text     => text,
  }

  # Check if pass happened
  begin
    $pass = @game_hash['game']['next_move']['type']
  rescue
    $pass = false
  end

  if $pass == 'pass'
    begin
      score          = false
      last_move_a    = last_move
      previous       = last_move_a[0]
      message_raw = [
        {
          'fallback'   => "#{previous} passed.",
          'pretext'    => "It's #{find_mention(player)}'s turn on BreakBase.",
          'text'       => "#{previous} passed.",
          'color'      => 'bad',
          'title'      => 'Pass',
          'title_link' => @breakbase_url,

        }
      ]

      message[:text]        = ''
      message[:attachments] = message_raw.to_json
    rescue => e
      puts "ERROR: #{e}"
    end
  elsif $pass == 'swap'
    begin
      score          = false
      last_move_a    = last_move
      previous       = last_move_a[0]
      num_letters    = @game_hash['game']['next_move']['num_letters']
      plural         = num_letters.to_i > 1 ? 's' : ''
      message_raw = [
        {
          'fallback'   => "#{previous} swapped #{num_letters} letter#{plural}.",
          'pretext'    => "It's #{find_mention(player)}'s turn on BreakBase.",
          'text'       => "#{previous} swapped #{num_letters} letter#{plural}.",
          'color'      => 'bad',
          'title'      => 'Swap',
          'title_link' => @breakbase_url,

        }
      ]

      message[:text]        = ''
      message[:attachments] = message_raw.to_json
    rescue => e
      puts "ERROR: #{e}"
    end
  end

  if score
    begin
      last_move_a = last_move
      previous    = last_move_a[0]
      words_a     = last_move_a[1]
      words_s     = words_a.join(', ').upcase
      points      = last_move_a[2]
      message_raw = [
        {
          'fallback'   => "#{previous} played #{words_s} for #{points} points.",
          'pretext'    => "It's #{find_mention(player)}'s turn on BreakBase.",
          'text'       => "#{previous} played #{words_s} for #{points} points.",
          'color'      => 'good',
          'title'      => 'Next turn',
          'title_link' => @breakbase_url,
          'thumb_url'  => "http://whatsaranjit.com/letters.php?text=#{words_a.first[0].upcase}"

        }
      ]

      message[:text]        = ''
      message[:attachments] = message_raw.to_json
    rescue => e
      puts "ERROR: #{e}"
    end
  end

  client.chat_postMessage(message)
  #client.auth_test
  @timer = 0
end

def game_score
  ret = Array.new
  begin
    sorted = @game_hash['game']['end_data'].sort_by { |id, score| -score }
    ret = sorted.map do |rank|
      if rank[1] == sorted.first[1]
        "*#{player_name(rank[0])}: #{rank[1]}*"
      else
        "#{player_name(rank[0])}: #{rank[1]}"
      end
    end
  rescue
    puts "[#{Time.now}] End_data does not exist"
  end
  ret.join("\n")
end

def notify_new
  Slack.configure do |config|
    config.token = @token
  end

  client     = Slack::Client.new
  @uids    ||= client.users_list['members']
  list_ids   = @game_hash['seated'] - @game_hash['request']['responses']
  list_names = ''

  list_ids.each do |id|
    list_names = "#{list_names} #{find_mention(player_name(id))}"
  end

  message = {
    :channel  => @channel,
    :username => 'Breakbase',
    :icon_url => 'https://pbs.twimg.com/profile_images/1364067224/icon.jpg',
  }

  message_raw = [
    {
      'fallback'   => "New game on BreakBase: #{@breakbase_url}#{list_names}",
      'pretext'    => "New game on BreakBase: #{@breakbase_url}#{list_names}",
      'text'       => game_score,
      'color'      => 'bad',
      'title'      => 'Game Score',
      'title_link' => @breakbase_url,

    }
  ]

  message[:text]        = ''
  message[:attachments] = message_raw.to_json

  client.chat_postMessage(message)
  @timer = 1
  return list_names
end

def do_it
  if @breakbase_cookie == ''
    anon_prompt       = bbase_get(@breakbase_enter)
    @breakbase_cookie = get_cookie(anon_prompt['Set-Cookie'])
    enter_button      = bbase_post(@breakbase_enter)
    @breakbase_cookie = get_cookie(enter_button['Set-Cookie'])
  end
  get_game            = bbase_get(@breakbase_url)
  #puts get_game.code

  # If successful login, remember cookie
  if get_game.code == '200'
    write_cookie
  else
    @breakbase_cookie == ''
  end

  @game_hash = parse_html(get_game.body)
  if check_new_game
    if (@timer == 0) || (@timer >= @new_reminder)
      unless quiet_hours?
        puts "[#{Time.now}] New game; notified:#{notify_new}"
      else
        @timer = @new_reminder - 600
        puts "[#{Time.now}] Quiet hours; new game supressed"
      end
    end
  elsif ! check_player(current_player_id)
    @current_player = current_player_id
    unless quiet_hours?
      notify_chat(player_name(current_player_id), true)
      puts "[#{Time.now}] New current player: #{player_name(current_player_id)}"
    else
      @timer = @reminder - 3600
      puts "[#{Time.now}] Quiet hours: New current player: #{player_name(current_player_id)}"
    end
  elsif @timer >= @reminder
    unless quiet_hours?
      notify_chat(player_name(current_player_id))
      puts "[#{Time.now}] Reminded player: #{player_name(current_player_id)}"
    else
      @timer = @reminder - 3600
      puts "[#{Time.now}] Quiet hours: Reminded player: #{player_name(current_player_id)}"
    end
  else
    puts "[#{Time.now}] Current player: #{player_name(current_player_id)}"
  end
end

while true do
  begin
    do_it
  rescue Exception => e
    puts e.message
    puts e.backtrace.inspect
  else
    # Debugging
    #exit 0 if ARGV[0]
    sleep @interval
    @timer += @interval
  end
end
