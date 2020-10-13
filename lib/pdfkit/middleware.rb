class PDFKit

  class Middleware

    def initialize(app, options = {}, conditions = {})
      @app        = app
      @options    = options
      @conditions = conditions
    end

    def call(env)
      @request    = Rack::Request.new(env)
      @render_pdf = false

      use_pdf = render_as_pdf?
      Rails.logger.info("##### render_as_pdf?: #{use_pdf}")
      set_request_to_render_as_pdf(env) if use_pdf
      status, headers, response = @app.call(env)
      Rails.logger.info("#### env app call: #{env['REQUEST_URI']}")
      Rails.logger.info("#### status app call: #{status}")
      Rails.logger.info("#### headers app call: #{headers.inspect}")

      if rendering_pdf? && headers['Content-Type'] =~ /text\/html|application\/xhtml\+xml/
        body = response.respond_to?(:body) ? response.body : response.join
        body = body.join if body.is_a?(Array)
        sum = Digest::MD5.hexdigest(body)
        Rails.logger.info("##### input checksum: #{sum}")
        Rails.logger.info("##################################### START BODY #{sum} #########################")
        Rails.logger.info(body)
        Rails.logger.info("##################################### END BODY #{sum} #########################")
        body = PDFKit.new(translate_paths(body, env), @options).to_pdf
        Rails.logger.info("##### output checksum: #{Digest::MD5.hexdigest(body)}")
        response = [body]

        # Do not cache PDFs
        headers.delete('ETag')
        headers.delete('Cache-Control')

        headers["Content-Length"]         = (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
        headers["Content-Type"]           = "application/pdf"
        Rails.logger.info("#### status at end: #{status}")
        Rails.logger.info("#### headers at end: #{headers.inspect}")
      end

      [status, headers, response]
    end

    private

    # Change relative paths to absolute
    def translate_paths(body, env)
      # Host with protocol
      root = PDFKit.configuration.root_url || "#{env['rack.url_scheme']}://#{env['HTTP_HOST']}/"

      body.gsub(/(href|src)=(['"])\/([^\"']*|[^"']*)['"]/, '\1=\2' + root + '\3\2')
    end

    def rendering_pdf?
      Rails.logger.info("##### rendering_pdf: #{@render_pdf}")
      @render_pdf
    end

    def render_as_pdf?
      request_path_is_pdf = @request.path.match(%r{\.pdf$})

      if request_path_is_pdf && @conditions[:only]
        rules = [@conditions[:only]].flatten
        rules.any? do |pattern|
          if pattern.is_a?(Regexp)
            @request.path =~ pattern
          else
            @request.path[0, pattern.length] == pattern
          end
        end
      elsif request_path_is_pdf && @conditions[:except]
        rules = [@conditions[:except]].flatten
        rules.map do |pattern|
          if pattern.is_a?(Regexp)
            return false if @request.path =~ pattern
          else
            return false if @request.path[0, pattern.length] == pattern
          end
        end

        return true
      else
        request_path_is_pdf
      end
    end

    def set_request_to_render_as_pdf(env)
      Rails.logger.info("##### in set_request_to_render_as_pdf")
      @render_pdf = true
      path = @request.path.sub(%r{\.pdf$}, '')
      %w[PATH_INFO REQUEST_URI].each { |e| env[e] = path }
      env['HTTP_ACCEPT'] = concat(env['HTTP_ACCEPT'], Rack::Mime.mime_type('.html'))
      env["Rack-Middleware-PDFKit"] = "true"
    end

    def concat(accepts, type)
      (accepts || '').split(',').unshift(type).compact.join(',')
    end

  end
end
