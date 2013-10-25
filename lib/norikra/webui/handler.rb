require 'norikra/error'
require 'norikra/logger'

require 'norikra/webui'

require 'sinatra/base'

class Norikra::WebUI::Handler < Sinatra::Base
  set :public_folder, File.absolute_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'public'))
  set :views, File.absolute_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'views'))

  enable :sessions

  def logger ; Norikra::Log.logger ; end

  def self.engine=(engine)
    @@engine = engine
  end

  def logging(type, handler, args=[], opts={})
    if type == :manage
      debug "WebUI", :handler => handler.to_s, :args => args
    else
      trace "WebUI", :handler => handler.to_s, :args => args
    end

    begin
      yield
    rescue Norikra::ClientError => e
      logger.info "WebUI #{e.class}: #{e.message}"
      if opts[:on_error_hook]
        opts[:on_error_hook].call(e.class, e.message)
      else
        halt 400, e.message
      end
    rescue => e
      logger.error "WebUI #{e.class}: #{e.message}"
      e.backtrace.each do |t|
        logger.error "  " + t
      end
      if opts[:on_error_hook]
        opts[:on_error_hook].call(e.class, e.message)
      else
        halt 500, e.message
      end
    end
  end

  def engine; @@engine; end

  def targets
    engine.targets.map(&:name)
  end

  get '/' do
    logging(:show, :index) do
      @page = "summary"

      input_data,session[:input_data] = session[:input_data],nil

      queries = engine.queries.sort
      pooled_events = Hash[* queries.map{|q| [q.name, engine.output_pool.pool.fetch(q.name, []).size.to_s]}.flatten]

      engine_targets = engine.targets.sort
      targets = engine_targets.map{|t| {name: t.name, auto_field: t.auto_field, fields: engine.typedef_manager.field_list(t.name) }}

      erb :index, :layout => :base, :locals => {
        input_data: input_data,
        stat: engine.statistics,
        queries: queries,
        pool: pooled_events,
        targets: targets,
      }
    end
  end

  post '/register' do
    query_name,query_group,expression = params[:query_name], params[:query_group], params[:expression]

    error_hook = lambda{ |error_class, error_message|
      session[:input_data] = {
        query_add: {
          query_name: query_name, query_group: query_group, expression: expression,
          error: error_message,
        },
      }
      redirect '/#query_add'
    }

    logging(:manage, :register, [query_name, query_group, expression], :on_error_hook => error_hook) do
      if query_name.nil? || query_name.empty?
        raise Norikra::ClientError, "Query name MUST NOT be blank"
      end
      if query_group.nil? || query_group.empty?
        query_group = nil
      end
      engine.register(Norikra::Query.new(:name => query_name, :group => query_group, :expression => expression))
      redirect '/#queries'
    end
  end

  post '/deregister' do
    query_name = params[:query_name]
    logging(:manage, :deregister, [query_name]) do
      engine.deregister(query_name)
      redirect '/#queries'
    end
  end

end