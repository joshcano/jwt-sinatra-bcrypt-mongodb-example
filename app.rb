require 'bundler'
Bundler.setup

require 'sinatra'
require 'openssl'
require 'haml'
require 'mongo_mapper'
require 'bcrypt'
require 'securerandom'
require 'jwt'

include BCrypt

MongoMapper.connection = Mongo::Connection.from_uri('mongodb://<user>:<pass>@<url>:<port>/<database_name`>')
MongoMapper.database = "testing_spread"

class User
  include MongoMapper::Document
  key :user, String
  key :firstname, String
  key :lastname, String
  key :pass, String
end

class Token
  include MongoMapper::Document
  key :user, String
  key :random, String
end

# go to this route to create a user account 
get '/create' do
  temp = User.new(
    :user => 'joshcano@gmail.com',
    :firstname => "Josh", 
    :lastname => "Cano", 
    :pass => BCrypt::Password.create('hello',:cost => 12)
  )
  temp.save!
  redirect '/'
end


signing_key_path = File.expand_path("../app.rsa", __FILE__)
verify_key_path = File.expand_path("../app.rsa.pub", __FILE__)

signing_key = ""
verify_key = ""

File.open(signing_key_path) do |file|
  signing_key = OpenSSL::PKey.read(file)
end

File.open(verify_key_path) do |file|
  verify_key = OpenSSL::PKey.read(file)
end

set :signing_key, signing_key
set :verify_key, verify_key

enable :sessions
set :session_secret, 'super secret' 

helpers do

  # authenticate the user using bcrypt returns true/false
  def authenticate(user, pass)
    if User.where(:user => user).first == nil
      puts "no user account"
    else
      if BCrypt::Password.new(User.where(:user => user).first.pass) == pass
        true
      else
        false
      end
    end
  end


  # protected just does a redirect if we don't have a valid token
  def protected!
    return if authorized?
    redirect to('/login')
  end

  # helper to extract the token from the session, header or request param
  # if we are building an api, we would obviously want to handle header or request param
  def extract_token
    # check for the access_token header
    token = request.env["access_token"]
    
    if token
      return token
    end

    # or the form parameter _access_token
    token = request["access_token"]

    if token
      return token
    end

    # or check the session for the access_token
    token = session["access_token"]

    if token
      return token
    end

    return nil
  end

  # check the token to make sure it is valid with our public key
  def authorized?
    @token = extract_token
    begin
      payload, header = JWT.decode(@token, settings.verify_key, true)


      @exp = header["exp"]

      # check to see if the exp is set (we don't accept forever tokens)
      if @exp.nil?
        puts "Access token doesn't have exp set"
        return false
      end

      @exp = Time.at(@exp.to_i)

      # make sure the token hasn't expired
      if Time.now > @exp
        puts "Access token expired"
        return false
      end

      # make sure the user only logs in once
      if Token.where(:random => payload["random"]).first == nil 
        puts "only one login per user at a time, bad random token"
        return false
      end

      @user_id = payload["user_id"]

    rescue JWT::DecodeError => e
      return false
    end
  end
end

get '/' do
  protected!
  haml :index
end

get '/login' do
  haml :login
end

get '/logout' do
  session["access_token"] = nil
  redirect to("/")
end

post '/login' do

  if authenticate(params[:username].downcase.delete(" "), params[:password])

    headers = {
      exp: Time.now.to_i + 60 #expire in 60 seconds
    }
    account = User.where(:user => params[:username].downcase.delete(" ")).first
    
    # using SecureRandom to create a unique random variable 
    randy = SecureRandom.base64
    
    if Token.where(:user => account[:user]).first == nil
      nil
    else
      Token.where(:user => account[:user]).first.delete 
    end

    only_one_user = Token.new(:user => account[:user],:random => randy)
    only_one_user.save! 

    @token = JWT.encode({user_id: account[:firstname], random: randy}, settings.signing_key, "RS256", headers)
    puts @token

    session["access_token"] = @token
    redirect to("/")
  else
    @message = "Username/Password failed."
    haml :login
  end
end

