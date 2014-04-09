require 'sinatra/base'
require 'sinatra/flash'

Encoding.default_internal = "utf-8"
Encoding.default_external = "utf-8"


class Spotyt < Sinatra::Base
	enable :sessions
	register Sinatra::Flash

	###############
	# => Config!  #
	###############
	set :session_secret, 'ADD_YOUR_OWN_SECRET_HERE'
	@@redis = Redis.new(:thread_safe => true)

	###############
	# => Methods! #
	###############
			# Gets Track Metadata from Spotify's Web Metadata API
			def get_track(spotify_id)
				content = HTTParty.get('http://ws.spotify.com/lookup/1/.json?uri=' + URI.escape("spotify:track:#{spotify_id}"))
				if !content.body.empty?
					json = Oj.load(content.body)
				else
					flash[:notice] = "Error with Spotify! Try again in 10 seconds!"
				end
			end

			#Finds the song on youtube
			# It does this by searching in format "Song Name - Artist" on youtube
			# Then it parses the XML data with nokogiri and picks the first video
			def youtube
				download = HTTParty.get("https://gdata.youtube.com/feeds/api/videos?q=#{URI.escape(@track)}")
				if !download.body.empty?
					doc = Nokogiri::HTML(download.body)
				    vids = doc.xpath('//link[contains(@href, "https://www.youtube.com/watch")]').to_a
				    video = vids.first
				    #Extracting the Video-ID
				    if video != nil
					    query_string = URI.parse(video["href"]).query
						parameters = Hash[URI.decode_www_form(query_string)]
					else
						youtube_no_video = "Can't find a decent YouTube mirror."
					end
				else
					flash[:notice] = "Error with Youtube! Try again in 30 seconds!"
				end
			end

			def latest
				@latest = @@redis.lrange("tracks",0,9)
			end

			#This method extracts the spotify track ID if the URI/URL is in the correct format
			#If it isn't then it returns false
			def extract_spotify_id(query)
				if query.start_with?('http://open.spotify.com/track/','https://open.spotify.com/track/','https://play.spotify.com/track/','http://play.spotify.com/track/')
					URI.split(query)[5].split("/")[2]
				elsif query.start_with?('spotify:track:')
					query.split(":")[2]
				else
					false
				end
			end

	###########################
	# => Routes & Controllers #
	###########################
	get '/' do

		latest

		haml :index
	end

	get '/fetch' do
		#Cache the page for 30 mins (mainly to reduce load on Redis since we can only have 10 max connections on the free plan)
		cache_control :public, max_age: 1800

		latest

		#Extracts the querys and then checks if the query is in the correct format.
		query = params[:query]
		@spotify_id = extract_spotify_id(query)
		if @spotify_id
			#If it is in the correct format it searches that query in Redis
			#If redis returns false (nil) then it goes ahead and makes requests to Spotify and Youtube
			redis_q = @@redis.get(@spotify_id)
			if !redis_q
				spotify = get_track(@spotify_id)["track"]

				@track = "#{spotify["name"]} - #{spotify["artists"][0]["name"]}"

				@video_id = youtube

				unless @video_id.include?("Can't find a decent YouTube mirror.")
					@video_id = youtube['v']
					#Caching results in redis
					result = Oj.dump({:track => @track,:video_id => @video_id})
					@@redis.pipelined do
						@@redis.set(@spotify_id, result)
						#Creates a list of tracks converted so we can create the latest 10 converts leaderboard
						@@redis.lpush("tracks", "#{@track}::#{@spotify_id}")
					end
				else
					@track = nil
					@video_id = nil
					flash[:notice] = "Can't find a decent YouTube mirror."
				end
			else
				#If the video has already been converted then it loads the data from redis and throws up the results
				result= Oj.load(redis_q)
				@track = result[:track]
				@video_id = result[:video_id]

			end
		else
			flash[:notice] = "Incorrect URI or URL! Try again!"
			redirect "/"
		end
		haml :index
	end

	#This is an API which does exactly the same as above but returns json
	#The format of the url is slightly different as you can probably tell
	#The format is:
	#http://www.spotify2tube.com/fetch/http://open.spotify.com/track/0pjjdauz55YnSJ8OsQKI3P
	# or
	#http://www.spotify2tube.com/fetch/spotify:track:5ZdzNVOmCSp5HFLk0EgvJS
	get '/fetch/*' do
		content_type :json
		#Cache the page for 30 mins (mainly to reduce load on Redis since we can only have 10 max connections on the free plan)
		cache_control :public, max_age: 1800

		#Extracts the querys and then checks if the query is in the correct format.
		query = params[:splat][0].gsub(":/","://")
		@spotify_id = extract_spotify_id(query)
		if @spotify_id
			#If it is in the correct format it searches that query in Redis
			#If redis returns false (nil) then it goes ahead and makes requests to Spotify and Youtube
			redis_q = @@redis.get(@spotify_id)
			if !redis_q
				spotify = get_track(@spotify_id)["track"]

				@track = "#{spotify["name"]} - #{spotify["artists"][0]["name"]}"

				@video_id = youtube
				unless @video_id.include?("Can't find a decent YouTube mirror.")
					@video_id = youtube['v']
					#Caching results in redis
					result = Oj.dump({:track => @track,:video_id => @video_id})
					@@redis.pipelined do
						@@redis.set(@spotify_id, result)
						#Creates a list of tracks converted so we can create the latest 10 converts leaderboard
						@@redis.lpush("tracks", "#{@track}::#{@spotify_id}")
					end
					Oj.dump({
							:spotify_id => @spotify_id,
							:track => @track,
							:youtube_video_id => @video_id,
							:youtube_url => "https://www.youtube.com/watch?v=#{@video_id}",
							:spotify2tube_url => "#{request.base_url}/fetch?query=spotify:track:#{@spotify_id}"
							})
				else
					@track = nil
					@video_id = nil
					Oj.dump({
								:error => "Can't find a decent YouTube mirror."
							})
				end
			else
				#If the video has already been converted then it loads the data from redis and throws up the results
				result= Oj.load(redis_q)
				@track = result[:track]
				@video_id = result[:video_id]
				Oj.dump({
						:spotify_id => @spotify_id,
						:track => @track,
						:youtube_video_id => @video_id,
						:youtube_url => "https://www.youtube.com/watch?v=#{@video_id}",
						:spotify2tube_url => "#{request.base_url}/fetch?query=spotify:track:#{@spotify_id}"
						})
			end
		else
			Oj.dump({:error => "Incorrect URI or URL! Try again!"})
		end
	end

	get '/sitemap.xml' do
		#Cache the page for 0.5 days (mainly to reduce load on Redis since we can only have 10 max connections on the free plan)
		cache_control :public, max_age: 43200
		links = @@redis.lrange("tracks",0,-1)

		map = XmlSitemap::Map.new('www.spotify2tube.com') do |m|
			m.add(:url => '/', :period => :daily, :priority => 1.0)
			links.each do |link|
				link = link.split("::")
				m.add(:url => "#{request.base_url}/fetch?query=spotify:track:#{URI.escape(link[1])}", :period => :weekly, :priority => 0.5)
			end
		end

		headers['Content-Type'] = 'text/xml'
		map.render
	end
end