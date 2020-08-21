class XPool
  require 'xchan'
  require 'rbconfig'
  require 'timeout'
  require_relative 'xpool/version'
  require_relative 'xpool/process'

  module ObjectMixin
    def xpool(size: )
      XPool.new(size: size)
    end
  end

  class ::Object
    include ObjectMixin
  end

  #
  # @param [Integer] size
  #  The number of processes to spawn.
  #
  # @return [XPool]
  #
  def initialize(size: )
    @pool = Array.new(size) { Process.new }
  end

  #
  # @param [Integer] number
  #  The number of processes to add to a pool.
  #
  # @return
  #   (see XPool#resize)
  #
  def expand(number)
    resize size + number
  end

  #
  # @param [Integer] number
  #  The number of processes to remove from a pool.
  #
  # @return
  #   (see XPool#resize)
  #
  def shrink(number)
    resize size - number
  end

  #
  # Broadcasts *job* to run on all processes in a pool.
  #
  # @example
  #   pool = xpool(size: 5)
  #   pool.broadcast(job)
  #   pool.shutdown
  #
  # @return [Array<XPool::Process>]
  #   Returns an array of {XPool::Process} objects.
  #
  def broadcast(job, *args)
    @pool.map {|process| process.schedule job, *args}
  end

  #
  # Performs a graceful shutdown of a pool.
  #
  # @param [Integer] timeout
  #   The number of seconds to wait before performing shutdown with `SIGKILL`.
  #
  # @return [void]
  #
  def shutdown(timeout: nil)
    if timeout
      begin
        Timeout.timeout(timeout) do
          @pool.each(&:shutdown)
        end
      rescue Timeout::Error
        @pool.each{|process| Process.kill 'SIGKILL', process.id}
      end
    else
      @pool.each(&:shutdown)
    end
  end

  #
  # Resize a pool and if shrinking the pool wait for processes to
  # finish their current job before letting them exit.
  #
  # @param [Integer] size
  #  The new size of the pool.
  #
  # @return [void]
  #
  def resize(new_size)
    new_size -= 1
    old_size = size - 1
    if new_size < 0
      @pool.each(&:shutdown)
      @pool = []
    elsif new_size == old_size
      # do nothing
    elsif new_size < old_size
      @pool[new_size+1..old_size].each(&:shutdown)
      @pool = @pool[0..new_size]
    else
      @pool += Array.new(new_size - old_size) { Process.new }
    end
  end

  #
  # Dispatch a job to a pool process.
  #
  # @param
  #   (see Process#schedule)
  #
  # @return [XPool::Process]
  #
  def schedule(job, *args)
    process = @pool.min_by(&:run_count)
    process.schedule job, *args
  end

  #
  # @return [Integer]
  #   Returns the number of processes in a pool.
  #
  def size
    @pool.size
  end
end
