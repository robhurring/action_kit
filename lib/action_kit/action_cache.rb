module ActionKit
  # Public: Basic interactor caching.
  module ActionCache
    extend ActiveSupport::Concern

    # Public: Caching strategy for ActionCache
    mattr_accessor :cache
    self.cache = ActionKit::Cache::Worthless

    # Public: Serializer to use for caching
    mattr_accessor :serializer
    self.serializer = ActionKit::Serializer::Marshal

    # Public: Context merging strategy.
    mattr_accessor :context_merge_strategy
    self.context_merge_strategy = ActionKit::MergeStrategy::Paranoid

    # Public: Globally enable/disable the action caching
    mattr_accessor :enabled
    self.enabled = true

    # Private: Check if action caching is enabled or not.
    def self.enabled?
      enabled
    end

    included do |_base|
      # Private: A proc that is given the `context` and used to generate a cache key.
      class_attribute :_cache_key_generator

      # Private: Options for our `cache`.
      class_attribute :_cache_options
      self._cache_options = {}

      # Private: Wrapper around our interactor that performs the caching.
      around :_cache
    end

    module ClassMethods
      # Public: A proc used to generate the cache key..
      #
      # block  - The key-generation method.
      #
      # Examples
      #
      #   cache_key do |context|
      #     "my-action:#{context.uuid}"
      #   end
      #
      # Returns nothing.
      def cache_key(&block)
        self._cache_key_generator = block
      end

      # Public: Cache options for our cache.
      #
      # time  - The expiration time for caching.
      #
      # Examples
      #
      #   expires_in 1.day
      #
      # Returns nothing.
      def expires_in(time)
        _cache_options[:expires_in] = time
      end

      # Public: Cache options for our caching strategy.
      #
      # options  - A list of options for our cache
      #
      # Examples
      #
      #   cache_options expires_in: 1.day
      #
      # Returns nothing.
      def cache_options(options = {})
        _cache_options = options
      end
    end

    private

    # Private: Run the interactor and cache the result. Caching will not be
    #          performed if the result is unsuccessful.
    #
    # cache_key  - Key for `Rails.cache`.
    # interactor - The interactor to cache.
    #
    # Returns the interactor result from cache.
    def _cache_action(cache_key, interactor)
      cache_options = self.class._cache_options

      result = ActionCache.cache.fetch(cache_key, cache_options) do
        interactor.call
        ActionKit.logger.debug "[cache.set] #{cache_key} -> #{cache_options}"
        ActionCache.serializer.dump(context)
      end

      restored_context = ActionCache.serializer.load(result)
      merged_context = ActionCache.context_merge_strategy.merge(
        context,
        restored_context
      )

      @context = merged_context
    end

    # Private: Wrap around the `interactor.call` and marshal the result into Rails.cache.
    #
    # interactor  - The interactor to be run.
    #
    # Returns the interactor result from cache.
    def _cache(interactor)
      key_generator = self.class._cache_key_generator

      if ActionCache.enabled? && key_generator
        cache_key = key_generator.call(context)
        _cache_action(cache_key, interactor)
      else
        interactor.call
      end
    end
  end
end
