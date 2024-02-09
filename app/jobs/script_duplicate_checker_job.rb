require 'zlib'

# This job should have three levels of locks on it:
#
# 1. Only one enqueued/running per script ID. Handled by sidekiq-unique-jobs.
# 2. Only two running at a time. Handled by ScriptDuplicateCheckerQueueingJob checking spare_processes.
# 3. Only one running per process. Handled by writing/deleting to cache with key run_process_cache_key.
class ScriptDuplicateCheckerJob
  include Sidekiq::Job

  DESIRED_RUN_COUNT = 2
  RUN_COUNTER_KEY = 'ScriptDuplicateCheckerJob-executing-count'.freeze
  RUN_PROCESS_KEY_PREFIX = 'ScriptDuplicateCheckerJob-executing-process-'.freeze

  # Really, should not expire, but we want to sure if something goes nuts we don't permanently stop running jobs.
  # lock_run! and unlock_run! will ensure the expiration date is refreshed if things are still moving.
  RUN_CACHE_EXPIRY = 30.minutes

  sidekiq_options queue: 'low', lock: :until_executed, on_conflict: :log, retry: 10_000

  # Retry more quickly so that we can stay at the start of the queue and not have ScriptDuplicateCheckerQueueingJob
  # slide in others before us.
  sidekiq_retry_in do |_count, exception|
    return 5.seconds if exception.is_a?(Sidekiq::MaxConcurrencyException)

    nil # Default behaviour
  end

  def perform(script_id)
    raise Sidekiq::MaxConcurrencyException if self.class.running_in_current_process?

    self.class.lock_run!

    begin
      now = Time.current

      begin
        script = Script.find(script_id)
      rescue ActiveRecord::RecordNotFound
        return
      end

      other_scripts = Script.where.not(id: script_id)

      last_run = ScriptSimilarity.where(script_id:).maximum(:checked_at)
      if last_run && script.code_updated_at < last_run
        # Eliminate the ones we are up to date on
        up_to_date_script_ids = ScriptSimilarity.where(script_id:).joins(:other_script).where(['code_updated_at < ?', last_run]).pluck(:other_script_id)
        other_scripts = other_scripts.where.not(id: up_to_date_script_ids)
      end

      [true, false].each do |tersed|
        results = CodeSimilarityScorer.get_similarities(script, other_scripts, tersed:)

        next if results.none?

        ScriptSimilarity.where(script_id:, tersed:).delete_all
        bulk_data = results.sort_by(&:last).last(100).map { |other_script_id, similarity| { script_id:, other_script_id:, similarity: similarity.round(3), checked_at: now, tersed: } }
        ScriptSimilarity.upsert_all(bulk_data)
      end

      ScriptPreviouslyDeletedChecker.perform_later(script_id) if last_run.nil?
    ensure
      self.class.unlock_run!
    end
  end

  def self.spare_processes
    running_processes = Rails.cache.fetch(RUN_COUNTER_KEY, raw: true, expires_in: RUN_CACHE_EXPIRY) { 0 }.to_i
    if running_processes < 0
      Rails.cache.write(RUN_COUNTER_KEY, 0, raw: true, expires_in: RUN_CACHE_EXPIRY)
      running_processes = 0
    end
    DESIRED_RUN_COUNT - running_processes
  end

  def self.lock_run!
    Rails.cache.increment(RUN_COUNTER_KEY, 1, expires_in: RUN_CACHE_EXPIRY, raw: true)
    Rails.cache.write(run_process_cache_key, true)
  end

  def self.unlock_run!
    Rails.cache.decrement(RUN_COUNTER_KEY, 1, expires_in: RUN_CACHE_EXPIRY, raw: true)
    Rails.cache.delete(run_process_cache_key)
  end

  def self.run_process_cache_key
    RUN_PROCESS_KEY_PREFIX + Process.pid.to_s
  end

  def self.running_in_current_process?
    Rails.cache.fetch(run_process_cache_key)
  end
end
