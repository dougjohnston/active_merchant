require 'rubygems'
require 'hpricot'
 
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class VancoGateway < Gateway
      TEST_URL = 'https://www.vancodev.com/cgi-bin/wstest2.vps'
      LIVE_URL = 'https://www.vancoservices.com/cgi-bin/ws2.vps'
      TOKEN_FILE = './tmp/vanco_token.txt'
      
      self.supported_countries = ['US']
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]
      self.homepage_url = 'http://www.vancoservices.com/'
      self.display_name = 'Vanco Services'
      
      def initialize(options = {})
        requires!(options, :url, :client_id, :login, :password)
        @options = options
        super
      end
      
      def purchase(creditcard, options = {})
        #@uniq = rand(1000)
        xml_data = build_purchase_request(creditcard, options)
        return commit('purchase', xml_data)
      end
    
      private
      
      def build_purchase_request(creditcard, options)
        xml = Builder::XmlMarkup.new#(:indent => 2)
        xml.VancoWS do
          xml.Auth do
            add_authentication(xml)
          end
          xml.Request do
            xml.RequestVars do
              xml.ClientID( @options[:client_id] )
              add_customer_data(xml, creditcard, options)
              add_creditcard(xml, creditcard)
              xml.Funds do
                add_funds(xml, options)
              end
              add_dates(xml, options)
            end
          end
        end
        return xml.target!
      end
      
      def add_authentication(xml)
        xml.RequestType( 'EFTAddCompleteTransaction' )
        xml.RequestID( 'cotn' + rand(100000).to_s )
        xml.RequestTime( Time.now.to_s(:vanco_time) )
        xml.SessionID( get_token() )
        xml.Version( 2 )
      end
      
      def add_customer_data(xml, creditcard, options)
        xml.CustomerName( "#{creditcard.last_name}, #{creditcard.first_name}" )
        xml.CustomerAddress1( options[:address1] )
        xml.CustomerAddress2( options[:address2] )
        xml.CustomerCity( options[:city] )
        xml.CustomerState( options[:state] )
        xml.CustomerZip( options[:zip] )
        xml.CustomerPhone( options[:phone] )
      end
      
      def add_creditcard(xml, creditcard)
        xml.AccountType( 'CC' )
        xml.AccountNumber( creditcard.number )
        xml.CardBillingName( "#{creditcard.name}" )
        xml.CardExpMonth( format(creditcard.month, :two_digits) )
        xml.CardExpYear( format(creditcard.year, :two_digits) )
        xml.SameCCBillingAddrAsCust( 'Yes' )
      end
      
      def add_funds(xml, options)
        options[:funds].each do |key, value|
          xml.Fund do
            xml.FundID( key.to_s )
            xml.FundAmount( sprintf("%.2f", value) )
          end
        end
      end
      
      def add_dates(xml, options)
        xml.StartDate( options[:start_date] )
        xml.FrequencyCode( options[:frequency] )
      end
      
      def commit(action, xml_request)
        data = xml_request.to_s
        # data = "#{CGI.escape(xml_request.to_s)}" # In Development
        headers = { "Content-Length" => data.length.to_s }
 
        response = ssl_post( @options[:url], data, headers )
 
        if action == 'token'
          return response
        elsif action == 'purchase'
          doc = Hpricot::XML(response)
          return Response.new(success_from(doc), message_from(doc), params_from(doc, xml_request, response))
        end
      end
      
      # Return false if there are errors, true if it was a success
      def success_from(doc)
        (doc/:Errors).inner_html.empty?
      end
      
      # Generic messages since the real detail will come across in params
      def message_from(doc)
        (doc/:Errors).inner_html.empty? ? "Success" : "Error"
      end
      
      # Return all the detail from the response
      def params_from(doc, request, response)
        params = {}
        params[:xml_request] = strip_cc(request)
        params[:xml_response] = response.strip
        if (doc/:Errors).inner_html.empty?
          params[:customer_id] = (doc/:Response/:CustomerRef).inner_html.to_i
          params[:payment_id] = (doc/:Response/:PaymentMethodRef).inner_html.to_i
          params[:transaction_id] = (doc/:Response/:TransactionRef).inner_html.to_i
        else
          params[:errors] = {}
          (doc/:Errors/:Error).each do |error|
            params[:errors][((error/:ErrorCode).inner_html).to_i] = (error/:ErrorDescription).inner_html
          end
        end
        return params
      end
      
      # Strip out the credit card number before storing it.
      def strip_cc(request)
        doc = Hpricot::XML(request)
        (doc/:AccountNumber).inner_html = '#####'
        doc.to_html
      end
      
      # Log into Vanco and obtain a SessionID token (good for 24 hours)
      # Grab the token from the file if it's valid. Otherwise, grab a new one.
      def get_token
        if valid_token_file?
          file = File.open(TOKEN_FILE, 'r')
          @session_id = file.read
          file.close
        else
          xml_data = build_token_request
          response = Hpricot::XML(commit('token', xml_data))
          @session_id = (response/:SessionID).inner_html
          file = File.new(TOKEN_FILE, 'w')
          file << @session_id
          file.close
        end
        return @session_id
      end
      
      def valid_token_file?
        # If the token file is present and was modified less than 24 hours ago
        # After early testing, the session id does not appear to last 24 hours so, we're setting it to 30 minutes
        File.exist?(TOKEN_FILE) and (File.mtime(TOKEN_FILE) > Time.now - 30)
      end
    
      def build_token_request
        xml = Builder::XmlMarkup.new
        xml.VancoWS do
          xml.Auth do
            xml.RequestType( 'Login' )
            xml.RequestID( 'cotn' + rand(10000000).to_s )
            xml.RequestTime( Time.now.to_s(:vanco_time) )
            xml.Version( 2 )
          end
          xml.Request do
            xml.RequestVars do
              xml.UserID( @options[:login] )
              xml.Password( @options[:password] )
            end
          end
        end
        xml.target!
      end
    end
  end
end