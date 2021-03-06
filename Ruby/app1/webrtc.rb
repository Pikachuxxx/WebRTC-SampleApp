#!/usr/bin/env ruby

# Copyright 2015 AT&T
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'sinatra'
require 'sinatra/config_file'

# Require codekit for token handling
require 'att/codekit'

include Att::Codekit

class WebRTC < Sinatra::Application
  #############################################
  ####### Configure the required values #######
  #############################################
  use Rack::Session::Cookie, 
    :key => 'rack.webrtc.session', 
    :path => "/",
    :secret => settings.session_secret

  configure do
    config_file 'config.yml'

    VTN_NUMBERS = settings.vtn_numbers.split(',')

    SCOPE='WEBRTC'
    AUTH_SCOPE='WEBRTCMOBILE'

    RestClient.proxy = settings.proxy
    FQDN = settings.fqdn
    Client = Auth::Client.new(settings.client_id, settings.client_secret)
    AuthCodeService = Auth::AuthCode.new(FQDN, Client.id, Client.secret, 
                                         :scope => AUTH_SCOPE,
                                         :redirect => settings.consent_redirect)
    CredService = Auth::ClientCred.new(FQDN, Client.id, Client.secret,
                                       :scope => SCOPE)
  end

  #############################################
  ####### Handlers for displaying pages #######
  #############################################

  get '/' do
    @auth_code = params[:code] if params[:code]
    erb :webrtc
  end

  ##############################################
  ###### RESTFul requests required by SDK ######
  ##############################################

  # Return the url required for consent to the SDK
  post '/oauth/authorize' do
    url = AuthCodeService.generateConsentFlowUrl
    { :consent_url => url }.to_json()
  end

  # Return a token to the SDK
  post '/oauth/token' do
    begin
      token = nil
      if request[:code]
        code = request[:code]
        token = AuthCodeService.createToken(code)
        session[:auth_token] = token
      else
        token = CredService.createToken
        session[:cred_token] = token
      end
      # store the most current created token for associate call
      session[:token] = token
      {
        :access_token => token.access_token,
        :refresh_token => token.refresh_token,
        :expires_in => token.expires_in
      }.to_json()
    rescue Exception => e
      puts e.backtrace
      status e.http_code
      body e.to_s
    end
  end

  post '/oauth/associate' do
    begin
      user = request[:user]
      url = "#{FQDN}/RTC/v1/userIds/#{user}"
      token = session[:token]

      headers = {
        :Authorization => "Bearer #{token.access_token}"
      }

      Transport.put(url, "", headers)
      201
    rescue Exception => e
      puts e.backtrace
      status e.http_code
      body e.to_s
    end
  end
end
