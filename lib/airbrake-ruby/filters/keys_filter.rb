module Airbrake
  module Filters
    ##
    # This is a filter helper that endows a class ability to filter notices'
    # payload based on the return value of the +should_filter?+ method that a
    # class that includes this module must implement.
    #
    # @see Notice
    # @see KeysWhitelist
    # @see KeysBlacklist
    module KeysFilter
      ##
      # @return [String] The label to replace real values of filtered payload
      FILTERED = '[Filtered]'.freeze

      ##
      # @return [Array<String,Symbol,Regexp>] the array of classes instances of
      #   which can compared with payload keys
      VALID_PATTERN_CLASSES = [String, Symbol, Regexp].freeze

      ##
      # @return [Integer]
      attr_reader :weight

      ##
      # Creates a new KeysBlacklist or KeysWhitelist filter that uses the given
      # +patterns+ for filtering a notice's payload.
      #
      # @param [Array<String,Regexp,Symbol>] patterns
      def initialize(logger, patterns)
        @logger = logger
        @patterns = patterns
        @valid_patterns = false
      end

      ##
      # This is a mandatory method required by any filter integrated with
      # FilterChain.
      #
      # @param [Notice] notice the notice to be filtered
      # @return [void]
      # @see FilterChain
      def call(notice)
        unless @valid_patterns
          eval_proc_patterns!
          validate_patterns
        end

        FILTERABLE_KEYS.each { |key| filter_hash(notice[key]) }

        if notice[:context][:user]
          if should_filter?(:user)
            notice[:context][:user] = FILTERED
          else
            filter_hash(notice[:context][:user])
          end
        end

        return unless notice[:context][:url]
        filter_url(notice)
      end

      ##
      # @raise [NotImplementedError] if called directly
      def should_filter?(_key)
        raise NotImplementedError, 'method must be implemented in the included class'
      end

      private

      def filter_hash(hash)
        hash.each_key do |key|
          if should_filter?(key)
            hash[key] = FILTERED
          elsif hash[key].is_a?(Hash)
            filter_hash(hash[key])
          end
        end
      end

      def filter_url_params(url)
        url.query = Hash[URI.decode_www_form(url.query)].map do |key, val|
          # Ruby < 2.2 raises InvalidComponentError if the query contains
          # invalid characters, so be sure to escape individual components.
          if should_filter?(key)
            "#{URI.encode_www_form_component(key)}=[Filtered]"
          else
            "#{URI.encode_www_form_component(key)}=#{URI.encode_www_form_component(val)}"
          end
        end.join('&')

        url.to_s
      end

      def filter_url(notice)
        begin
          url = URI(notice[:context][:url])
        rescue URI::InvalidURIError
          return
        end

        return unless url.query
        notice[:context][:url] = filter_url_params(url)
      end

      def eval_proc_patterns!
        return unless @patterns.any? { |pattern| pattern.is_a?(Proc) }

        @patterns = @patterns.flat_map do |pattern|
          next(pattern) unless pattern.respond_to?(:call)
          pattern.call
        end
      end

      def validate_patterns
        @valid_patterns = @patterns.all? do |pattern|
          VALID_PATTERN_CLASSES.any? { |c| pattern.is_a?(c) }
        end

        return if @valid_patterns

        @logger.error(
          "#{LOG_LABEL} one of the patterns in #{self.class} is invalid. " \
          "Known patterns: #{@patterns}"
        )
      end
    end
  end
end
