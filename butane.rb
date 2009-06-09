#!/usr/bin/env ruby
require 'rubygems'
require 'tinder'
require 'yaml'

def notify(title, message = "", options = {})
  img_opt = "-i #{options[:image]}" if options[:image]
  delay_opt = ""
  priority_opt = ""
  if options[:delay]
    delay_opt = "-t #{options[:delay]}"
  end

  if options[:priority]
    priority_opt = "-u #{options[:priority]}"
  end

  # Cleanse the message
  msg = message.dup
  msg.gsub! /'/, ''       # Get rid of single quotes since we use 'em to delimit msg
  msg.gsub! '\u003E', '>'
  msg.gsub! '\u003C', '<'
  msg.gsub! '\u0026', '&'
  msg.gsub! '\"', '"'
  msg.gsub! '&hellip;', '...'   # notify-send don't like this

  # And let's remove all but the href attribute in any anchors
  # in the msg.  Assumes that in href=stuff, stuff has no whitespace.
  msg.gsub! /<a[^>]+(href=[^(\s|>)]+)[^>]*>/, '<a \1>'

  `notify-send #{delay_opt} #{priority_opt} #{img_opt} \"#{title}\" '#{msg}'`
end

def monitor_room(room, config = {})
  sticky = config[:sticky]
  ignore = config[:ignore]

  room_name = room.name.gsub /"/, '' # Get rid of any dquotes since we use 'em to delimit person

  last_message_id = 0
  room.listen do |m|
    # Ignore any pings from campfire to determine if I'm still
    # here
    next if m[:person].strip.empty?  # Ignore anything from a nil / empty person

    next if m[:id].to_i <= last_message_id
    last_message_id = m[:id].to_i

    delay = 20000 # in milliseconds (time to display the notification)
    priority = "normal"

    # If we're to monitor something in particular in this room, set the 
    # delay notification to zero which will leave the message up until
    # clicked away.
    if sticky && m[:message] =~ /#{sticky}/i
        delay = 0
        priority = "critical"
    end

    if ignore
      next if m[:message] =~ /#{ignore}/
    end

    person = m[:person].gsub /"/, ''  # Get rid of any dquotes since we use 'em to delimit person

    notify("#{person} in #{room_name}", m[:message], :delay => delay, :image => config[:image], :priority => priority)
  end
  notify "Stopped monitoring #{room.name} for some reason", "", :delay => 0, :priority => "critical"
end

config = YAML::load_file("#{ENV['HOME']}/.butanerc")
account_names = config.keys

threads = []
account_names.each do |account_name|
  rooms = config[account_name][:rooms]
  account_img = config[account_name][:image]
  if rooms && rooms.size > 0
    campfire = Tinder::Campfire.new account_name,
                                    :ssl => config[account_name][:ssl]
    begin
      campfire.login config[account_name][:login], config[account_name][:password]
    rescue Tinder::Error => e
      notify "Problem logging in to #{account_name}", "#{e.message}"
      next
    end
    notify "Successfully logged in to #{account_name}", "", :image => account_img

    # Start up a thread for each room we are going to monitor
    rooms.keys.each do |room_name|
      room = campfire.find_room_by_name room_name
      if room
        room_cfg = rooms[room_name] || {}
        room_cfg[:image] ||= account_img
        notify "Now monitoring #{room_name}", "", :image => room_cfg[:image]
        threads << Thread.new(room, room_cfg) do |r, cfg|
          monitor_room(r, cfg)
        end
      else
        notify "Did not find #{room_name}, not monitoring"
      end
    end
  end
end

threads.each { |t| t.join }
