Spotify2Tube
============

Quickly convert your Spotify URLs and URIs into Youtube Links so you can share them easily around the web.

You can find it online at:
[www.spotify2tube.com](www.spotify2tube.com)

![Demo Screenshot](https://s3.amazonaws.com/f.cl.ly/items/0T27213w0Q172g082D1z/Screen%20Shot%202014-04-09%20at%2017.13.13.png)


## The 3 Step Setup
	- Make sure you have a Redis server up and running (You edit the values in the app.rb file)
	- If you want caching to work then you will also want Memcache servers running (You can edit values in the config.ru)


1. Clone Repo

	```bash
	git clone git@github.com:BukhariH/Spotify2Tube.git
	```

2. Install dependencies

	```bash
	bundle install
	```

3. Start the server

	```bash
	foreman start
	```
