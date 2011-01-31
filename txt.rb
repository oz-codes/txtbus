require 'sinatra' #Gotta have sinatra to even get this to think to work.
require 'haml'
require "digest/md5" #user authentication
require 'cgi' #html escaping, etc
require 'net/smtp' #sending email
require 'includes/conf' #main conf file

enable :sessions #cookie based sessions for login tracking

def send_email(from, from_alias, to, to_alias, subject, message) #Sending emails!
	msg = <<END_OF_MESSAGE
From: #{from_alias} <#{from}>
To: #{to_alias} <#{to}>
Reply-to: noreply@sirmxe.info
Subject: #{subject}
	
#{message}
END_OF_MESSAGE
	
	Net::SMTP.start('127.0.0.1') do |smtp|
		smtp.send_message msg, from, to
	end
end

def send_confirmation(to,username,password) #wrapper for sending confirmation email
	send_email("no-reply@sirmxe.info","no-reply@sirmxe.info",to,to,"Welcome to txtbus!","Welcome to txtbus. Your login information is:\nUsername: #{username}\nPassword: #{password}")
end

class NotLoggedInError<Exception
	
end

get '/install' do	#Install me!
	haml :install
end

post '/install' do #What to do..
	msg = ""
	#gathering info
	name = params[:name]
	admin = params[:admin]
	prefix = params[:prefix]
	email = params[:email]
	password = params[:password]
	dbname = params[:db]
	dbuser = params[:dbuser]
	dbpass = params[:dbpass]
	dbhost = params[:dbhost]	
	#connecting to db
	db = Mysql::new(dbhost,dbuser,dbpass,dbname)
	#creating tables.
	msg = "Creating main database...\n"
	begin
		#table: main
		db.query("CREATE TABLE IF NOT EXISTS `#{prefix}_main` (
		  `id` int(11) NOT NULL auto_increment,
		  `usertype` int(11) NOT NULL default '0' COMMENT '0=regular,1=mod,2=admin',
		  `username` varchar(20) NOT NULL,
		  `password` varchar(32) NOT NULL,
		  `email` varchar(128) NOT NULL,
		  `name` varchar(128) NOT NULL,
		  `created` int(11) NOT NULL,
		  `info` varchar(140) NOT NULL,
		  `nick` varchar(64) NOT NULL,
		  `lastupdate` int(11) NOT NULL,
		  `lastupdatetxt` varchar(160) NOT NULL,
		  PRIMARY KEY  (`id`)
		) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;
		")
	rescue Mysql::Error => e #An error occurred?
		msg += "Could not create main table: #{e.error} (#{e.errno})\n" #log it
		error = true
	end
	msg += "Creating followers table...\n"
	begin
		#table: followers ...
		db.query("CREATE TABLE IF NOT EXISTS `#{$prefix}_followers` (
	  `id` int(11) NOT NULL auto_increment,
	  `userid` int(11) NOT NULL,
	  `followerid` int(11) NOT NULL,
	  `time` int(11) NOT NULL,
	  PRIMARY KEY  (`id`)
	) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ; 
	")
	rescue Mysql::Error => e
		msg += "Could not create followers table: #{e.error} (#{e.errno})\n"
		error = true
	end
	msg += "Creating status table...\n"
	begin
		#table: status
		db.query("CREATE TABLE IF NOT EXISTS `#{$prefix}_status` (
		  `id` int(11) NOT NULL auto_increment,
		  `userid` int(11) NOT NULL,
		  `status` varchar(160) NOT NULL,
		  `when` int(11) NOT NULL,
		  PRIMARY KEY  (`id`)
		) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=1 ;")
	rescue Mysql::Error => e
		msg += "Could not create status table: #{e.error} (#{e.errno})\n"
		error = true
	end
	if !error then #No errors? Good
		#Creating admin user
		msg += "Inserting admin data in...\n"
		begin 
			db.query("INSERT INTO #{$prefix}_main (usertype, username,password,email,created) VALUES (2,'#{Mysql::escape_string(username)}','#{Digest::MD5.hexdigest(password)}','#{Mysql::escape_string(email)}',#{Time.now.to_i})")
			info = "set :name, '#{name}'\n\$host='#{dbhost}'\n\$user='#{dbuser}'\n\$pass='#{dbpass}'\n\$db='#{dbname}'\ninclude './sql.rb'"
			File.open("includes/conf.rb","w") do |f| #Writing conf file
				f.write(info)
			end
		rescue Mysql::error => e
			#oh no, it didn't work!
			msg += "Could not create admin user: #{e.error} (#{e.errno})"
		end
	else #errors :(
		msg += "There were some errors in your install. Try installing again?"
	end 
	haml :msg, :locals => {:msg => msg} #render message output page
end

before do 
	if $installed==false then #if installed isn't set, then rewrite path to /install
		request.path_info = "/install"
	end
end

error NotLoggedInError do #no use right now
	haml :notloggedin #ignore me
end			  #yea

def getName(id,db) #Get username from user id
	row=db.query("SELECT username,nick,name FROM #{$prefix}_main WHERE id=#{id}").fetch_hash() #run query
	if row['nick'] != "" then #if nick is set, then use that
		name = row['nick']
	elsif row['name'] != "" then #otherwise, use their first name
		name = row['name'].split(" ")[0];
	else #okay, just use their username.
		name = row['username']
	end
	return name
end

before do #database keepalive.
	begin
		db.ping() #ping the database to see if it's still responding
	rescue Mysql::Error => msg #it's not? cool.
		db = Mysql::new($host,$user,$pass,$db) #bring the database back up if it's dead
	end
end
get '/' do #index page
	haml :index
end

get '/about' do	#about page
	haml :about
end

get '/list' do #debugging purposes. list users.
	users = Array.new
	db.query("SELECT id FROM #{$prefix}_main").each_hash do |row|
		id = row['id'].to_i
		name = getName(id,db) 
		users[id]=name;	
	end
	#puts users
	haml :list, :locals => {:usr => users}
end

def getFollowers(id,db) #get all of the followers for user with id: id
	followers = Array.new	#followers array
	db.query("SELECT followerid FROM #{$prefix}_followers WHERE userid=#{id}").each_hash do |row| 
		fi = row["followerid"].to_i #get id
		followers.push(fi) #put it in the array
	end
	return follower #return the array
end

def getFollowing(id,db) #get all users that userid id is following
	following = Array.new #following array	
	db.query("SELECT userid FROM #{$prefix}_followers WHERE followerid=#{id}").each_hash do |row|
		ui = row["userid"] #get id
		following.push(ui) #push to array
	end
	return following #return it
end
	
	
get '/list/:id' do  #debugging purposes
	sql = ""
	followers = "";
	following = "";
	db.query("SELECT * FROM #{$prefix}_main WHERE id=#{params[:id]}").each_hash do |row|
		row.each do |field, val|
			sql += "#{field}: #{val}\n"
		end
	end
	f = getFollowers(params[:id],db);
	if f.length == 0 then
		followers = "None"
	else 
		followers = "Followed by #{f.length} people<br />";
		f.each do |id|
			name = getName(id,db)
			followers += "<a href='../list/#{id}'>#{name}</a><br />"
		end
	end
	f = getFollowing(params[:id],db);
	if f.length == 0 then
		following = "No one"
	else 
		following = "Following #{f.length} people<br />"
		f.each do |id|
			name = getName(id,db)
			following += "<a href='../list/#{id}'>#{name}</a><br />"
		end
	end
	haml :id, :locals => {:sql => sql, :followers => followers, :following => following}
end

get %r{/updates(/?|/(\d+))?} do #most recent updates. debugging purposes.
	if params[:captures].length == 0 then
		curPage = 0
		page = 0
	else
		page = params[:captures][2].to_i
		num = page*10
	end
	list ="" 
	i = 0;
	q = db.query("SELECT DISTINCT userid,`status`,`when` FROM #{$prefix}_status ORDER BY `when` DESC LIMIT #{num},10")
	num = (q.num_rows()/10).to_i;
	q.each_hash do |row|
		db.query("SELECT name,nick FROM #{$prefix}_main WHERE id=#{row['userid']}").each_hash do |row2|
			name = getName(row['userid'],db);
			status = row["status"];
			whn = row["when"].to_i;
			t = Time.at(whn);
			list += "#{name}: #{status} (Posted #{t.strftime('%m/%d/%Y at %I:%M%p')})<br />\n";
		end
	end
	haml :updates, :locals => {:current => page, :output => list, :pages => num}	
end

#get '/kill' do
#	haml :kill, :locals => {:pid => Process.pid, :act => "kill"}	
#end
before '/user/:username' do #rewrite url to go where it should
	request.path_info = "/user/#{params[:username]}/1"
end

def addFollower(id,who,db) #add userid id as a follower to userid who
	msg = ""
	begin #let's try
		db.query("INSERT INTO #{$prefix}_followers (userid,followerid,time) VALUES (#{who},#{id},#{Time.now.to_i})");
		msg = "You are now following that person." #success!
	rescue Mysql::Error => e #error :(
		msg = "Could not follow user: #{e.error} (#{e.errno})" #couldn't follow
	end
	return msg #return it
end

def removeFollower(id,who,db)  #remove userid id as a follower of userid who
	msg = ""
	begin	#let's try...
		db.query("DELETE FROM #{$prefix}_followers WHERE userid=#{who} AND followerid=#{id}")
		msg = "You are no longer following that person." #success!
	rescue Mysql::Error => e #no :(
		msg = "Could not unfollow user: #{e.error} (#{e.errno})" #phail
	end
	return msg
end
	

get '/follow/:id' do #follower user with id :id
	id = params[:id]
	msg = ""
	if session[:loggedin] != true then #why try to follow if not logged in?
		msg = "You can't follow someone if you're not logged in."
	elsif id == session[:id] then #can't follow yourself
		msg = "You can't follow yourself!"
	elsif isFollowing(session[:id],id,db) then #already following 'em? then don't try again.
		msg = "You're already following this person."
	else
		msg = addFollower(session[:id],id,db) #add yourself as follower to person
	end
	haml :msg, :locals => {:msg => msg}	#render msg page with output
end

get '/unfollow/:id' do #same as follow/:id except unfollow
	id = params[:id]
	msg = ""
	if session[:loggedin] != true then #can't unfollow if you're not logged in
		msg = "You can't unfollow someone if you're not logged in."
	elsif id == session[:id] then #can't unfollow yourself (can't follow either)
		msg = "You can't unfollow yourself!"
	elsif !isFollowing(session[:id],id,db) then #not following them? then why are you trying to unfollow them?
		msg = "You're not following this person."
	else
		msg = removeFollower(session[:id],id,db) #remove follower.
	end
	haml :msg, :locals => {:msg => msg}	#same as above
end
get %r{/user/(.+)/(\d+)?} do |username, page| #list user updates
	opts = ""
	page = page.to_i #page
	page -= 1 #-1 for querificationz
	num = page*10 #LIMIT clause fix
	statuses = Array.new #status updates
	times = Array.new #times for the updates
	ids = Array.new #status id's
	id = q({:what => "id", :rel => "LIKE", :row=>"username",:val=>"'#{username}'", :db=>db}); #get user id
        q = db.query("SELECT DISTINCT `id`,`status`,`when` FROM #{$prefix}_status WHERE userid=#{id} ORDER BY `when` DESC LIMIT #{num},10") #get statuses
	pages = (db.query("SELECT DISTINCT `status` FROM #{$prefix}_status WHERE userid=#{id}").num_rows()/10).to_i #page count 
	if id != session[:id] && session[:loggedin] then #can we follow 'em? are welogged in, and not them?
		following = q({:what => "followerid", :row=>"userid",:val=>id,:table=>"#{$prefix}_followers",:db=>db}) #check if following
		if following == -1 then #nope, let's unfollow
			opts = "<a href='/follow/#{id}'>Follow</a>"
		else #yep, wanna unfollow?
			opts = "<a href='/unfollow/#{id}'>Unfollow</a>"
		end #no other criteria.
	end
        q.each_hash() do |row| #put information in
			ids.push(row['id']) #post id
			statuses.push(row['status']) #status
			times.push(row['when'].to_i) #status post time
        end
        haml :user, :locals => {:opts => opts,:current => page, :ids => ids,:stats => statuses, :times=> times, :username => username, :pages => pages} #render user with the options given
end

def isFollowing(id,who,db) #check if userid id is following userid who
	return db.query("SELECT * FROM #{$prefix}_followers WHERE userid=#{who} AND followerid=#{id}").num_rows() != 0
end

get '/delete/update/:id' do #delete updates
	id = params[:id]
	userid = q({:what => "userid", :row=>"id",:val=>id,:table=>"#{$prefix}_status",:db=>db}) #get userid from this post
	if !(session[:id] == userid || session[:usertype] > 0) #if you're not them, or you aren't an admin/mod...
		haml :notallowed, :locals=>{:owner => q({:what=>"username",:row=>"id",:val=>userid})} #you're outta here!
	else
		db.query("DELETE FROM #{$prefix}_status WHERE id=#{id}") #delete it
		haml :delete, :locals=>{:id=>id} #render delete.haml
	end
end

#get '/reload' do
#	haml :kill, :locals => {:pid => Process.pid, :act => "reload"}	
#end
get '/login' do #login page
	haml :login
end

def getRow(args) #get row where id = args[:id]
	#args format: 
	#id: userid
	#db: database instance
	id = args[:id]
	db = args[:db]
	return db.query("SELECT * FROM #{$prefix}_main WHERE id=#{id}").fetch_hash()
end

def q(args) #wrapper for queries
	#args: hash, opts:
	#what: what row you want
	#row: what row you are using to search by
	#rel: what relation (i.e. = or LIKE
	#val: what value to compare to
	#db: your database connexion
	what = Mysql::escape_string(args[:what])
	row = args[:row]
	db = args[:db]
	val = args[:val]
	table = (args[:table]) ? args[:table] : "txt"
	rel = (args[:rel]) ? args[:rel] : "=";
	query = "SELECT #{what} FROM #{table} WHERE #{row} #{rel} #{val}" #query
	hash = db.query(query).fetch_hash(); #do query, fetch hash
	if what == "*" then 
		#user wanted the whole hash, take it
		return hash
	elsif !hash.nil? 
		#return what the user wanted
		return hash[what] 
	else 
		#return -1 for PHAIL
		return -1
	end
end

get '/update' do #post an update
	if !session[:loggedin] then
		haml :notloggedin #not logged in
	else
		haml :update #render page
	end
end
get '/post' do #see above
	if session[:loggedin] != true then
		haml :notloggedin
	else
		haml :update 
	end
end

get '/register' do #register user
	haml :register
end

post '/register' do
	msg = ""
	username = params[:username]
	password = params[:password]
	p2 = params[:password2]
	email = params[:email]
	e2 = params[:email2]
	info = params[:info]
	error = false
	if username == "" then #no username?
		msg = "You didn't provide a username."
		error = true
	elsif password == "" then #no password?
		msg = "You didn't provide a password."
		error = true
	elsif email == "" then #no email?
		msg = "You didn't provide an email address"
		error = true
	elsif(password != p2) then #confirmation password wrong?
		msg = "Passwords did not match."
		error = true
	elsif email != e2 then #email confirmation wrong?
		msg = "Emails did not match"
		error = true
	elsif username.length > 20 then #username too long?
		msg = "Username greater than 20 characters. Please retry."
		error = true
	elsif q({:what => "email", :row=>"email",:val=>"'#{email}'",:db=>db}) != -1 then #email already in use?
		msg = "Email already in use"
		error = true
	elsif q({:what => "username", :row=>"username",:val=>"'#{username}'",:db=>db}) != -1 then #username already in use?
		msg = "Username already in use"
		error = true
	else #nothing's wrong, let's do this
		pash = Digest::MD5.hexdigest(password); #password hash
		user = Mysql::escape_string(username) #escaping str for injection bulletproofing
		info = Mysql::escape_string(info) #...
		mail = Mysql::escape_string(email) #...
		created = Time.now.to_i #when it was created
		begin #let's try creating a user
			#create user
			q = db.query("INSERT INTO #{$prefix}_main (username,password,info,email,created) VALUES ('#{user}','#{pash}','#{info}','#{mail}',#{created})")
			msg = "Successfully joined! Login at <a href='/login'>this link</a>"
		rescue Mysql::Error => e #didn't work...
			msg = "Could not register with the given credentials. Error message was: #{e.error} (Err#{e.errno})";
			#error!
			error = true
		end
	end
	send_confirmation(email,username,password) unless error #send confirmation message if ther was no error
	haml :doregister, :locals => {:imesg=>msg} #render doregister.haml
end

post '/update' do #post an update
	if session[:loggedin] != true then #can't do it if you're not logged in...
		haml :notloggedin
	else
		update = Mysql::escape_string(CGI.escapeHTML(params[:update])) #kill html out
		msg = ""
		begin #push to db
			db.query("INSERT INTO #{$prefix}_status (`status`,`when`,`userid`) VALUES ('#{update}',#{Time.now.to_i},#{session[:id]})"); #push update in
			db.query("UPDATE #{$prefix}_main SET lastupdate=#{db.insert_id()} WHERE id=#{session[:id]}") #update last update
			db.query("UPDATE #{$prefix}_main SET lastupdatetxt='#{update}' WHERE id=#{session[:id]}") #update last update txt
			msg = "Successfully updated: #{update}"
		rescue Mysql::error => e #errorroro
			msg = "Error: #{db.error} (#{db.errno})"
		end
		haml :postupdate, :locals => {:msg => msg}
	end
end
	
get '/hash' do #just outputs the mysql hash generated upon logging in
	out = ""
	if session[:loggedin] != true then
		haml :notloggedin
	else 	
		session[:hash].each do |k, v|
			out += "#{k}: #{v}<br/>\n"
		end
		haml :hash, :locals => {:output => out}
	end
end

before '/users' do
        request.path_info = "/users/1" #rewrite /users to /users/1 to keep path proper
end
get %r{/users/(\d+)} do |page| #view list of users, and each page
        page = page.to_i #which page?
        page -= 1 #subtract one for proper querification.
        num = page*10 #first option in MySQL LIMIT
        q = db.query("SELECT DISTINCT username,created FROM #{$prefix}_main ORDER BY created ASC LIMIT #{num},10") #get username
        pages = (db.query("SELECT DISTINCT `username` FROM #{$prefix}_main").num_rows()/10).to_i #get total number of users
	users = Array.new
        q.each_hash() do |row|
		users.push(row["username"]) #push the user into the array.
        end
        haml :users, :locals => {:current => page, :users => users, :times=> times, :pages => pages} #render users with current page, and which users there are
end

post '/login' do #log in 
	uname = params[:uname]
	pass = params[:pass]
	pash = Digest::MD5.hexdigest(pass); #pass hash
	login = db.query("SELECT * FROM #{$prefix}_main WHERE username LIKE '#{Mysql.escape_string(uname)}' AND password = '#{pash}'") #check if it works
	if login.num_rows() == 1 then #did you log in?
		session[:username] = uname #username!
		session[:loggedin] = true #logged in - true
		session[:id] = q({:what => "id", :row => "username", :val => "'#{uname}'", :db => db}) #userid
		session[:usertype] = q({:what => "usertype", :row=>"id", :val=>session[:id], :db => db}).to_i #user type
		session[:hash] = getRow({:id => session[:id], :db => db}) #sql hash
	else #phail
		session[:loggedin] = false #not logged in
	end
	haml :inlog, :locals => {:success => session[:loggedin]} 	#login page
end

get '/logout' do #logout
	session[:loggedin] = false
	session.delete_if do |k,v|
		k == :loggedin || k == :hash
	end
	haml :logout #pretty simple
end
	

get '/fmap' do #make a mop of who follows who.
	map = "";
	db.query("SELECT userid,followerid FROM #{$prefix}_followers").each_hash do |row| #get info from followers table
		ui = row["userid"]; #who is being followed?
		fi = row["followerid"]; #who is following them?
		user = getName(ui,db); #get user name
		follower = getName(fi,db); #same
		map += "<a href='list/#{ui}'>#{user}</a> <- <a href='list/#{fi}'>#{follower}</a><br />" #add info to map
	end
	haml :fmap, :locals => {:map => map} #render fmap.haml with followmap
end
