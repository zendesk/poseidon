class TestCluster
  attr_reader :broker, :zookeeper
  def initialize
    @zookeeper = ZookeeperRunner.new
    @broker = BrokerRunner.new(0, 9092)
  end

  def start
    @zookeeper.start
    @broker.start
  end

  def stop
    # The broker will end up in a state where it ignores SIGTERM
    # if zookeeper is stopped before the broker.
    @broker.stop
    spec_sleep(5, "TestCluster::broker.stop")

    @zookeeper.stop
  end
end

class JavaRunner
  KILL_SIGNALS = {
    sigterm: 15,
    sigkill: 9
  }
  def self.remove_tmp
    FileUtils.rm_rf("#{POSEIDON_PATH}/tmp")
  end

  def self.set_kafka_path!
    if ENV['KAFKA_PATH']
      JavaRunner.kafka_path = ENV['KAFKA_PATH']
    else
      puts "******To run integration specs you must set KAFKA_PATH to kafka src directory. See README*****"
      exit
    end
  end

  def self.kafka_path=(kafka_path)
    @kafka_path = kafka_path
  end

  def self.kafka_path
    @kafka_path
  end

  def initialize(id, start_cmd, pid_cmd, kill_signal, properties = {})
    @id = id
    @properties = properties
    @start_cmd = start_cmd
    @pid_cmd = pid_cmd
    @kill_signal = KILL_SIGNALS[kill_signal] || 9
    @stopped = false
  end

  def start
    write_properties
    run
  end

  def stop
    if !@stopped
      killed_at = Time.now
      loop do
        if (pid = `#{@pid_cmd}`.to_i) == 0
          SPEC_LOGGER.info "Killed."
          break
        end

        if Time.now - killed_at > 30
          raise "Failed to kill process!"
        end

        SPEC_LOGGER.info "Sending signal #{@kill_signal} to #{pid}"
        SPEC_LOGGER.info "(#{@start_cmd})"
        system "kill -#{@kill_signal} #{pid} > /dev/null 2>&1"

        spec_sleep 0.5, "In loop with KILL"
      end

      @stopped = true
    end
  end

  def without_process
    stop
    begin
      yield
    ensure
      start
      spec_sleep 5, "JavaRunner::without_process, ensuring process has started"
    end
  end

  private

  def run
    FileUtils.mkdir_p(log_dir)
    system "LOG_DIR=#{log_dir} #{@start_cmd} #{config_path} >> tmp/log/stdout.log 2>&1 &"
    @stopped = false
  end

  def write_properties
    FileUtils.mkdir_p(config_dir)
    File.open(config_path, "w+") do |f|
      @properties.each do |k,v|
        f.puts "#{k}=#{v}"
      end
    end
  end

  def log_dir
    "#{file_path}/log"
  end

  def config_path
    "#{config_dir}/#{@id}.properties"
  end

  def config_dir
    "#{file_path}/config"
  end

  def file_path
    POSEIDON_PATH + "/tmp/"
  end
end

class BrokerRunner
  DEFAULT_PROPERTIES = {
    "broker.id" => 0,
    "port" => 9092,
    "num.network.threads" => 2,
    "num.io.threads" => 2,
    "socket.send.buffer.bytes" => 1048576,
    "socket.receive.buffer.bytes" => 1048576,
    "socket.request.max.bytes" => 104857600,
    "log.dir" => "#{POSEIDON_PATH}/tmp/kafka-logs",
    "num.partitions" => 1,
    "log.flush.interval.messages" => 10000,
    "log.flush.interval.ms" => 1000,
    "log.retention.hours" => 168,
    "log.segment.bytes" => 536870912,
    #"log.cleanup.interval.mins" => 1,
    "zookeeper.connect" => "localhost:2181",
    "zookeeper.connection.timeout.ms" => 1000000,
    #"kafka.metrics.polling.interval.secs" => 5,
    #"kafka.metrics.reporters" => "kafka.metrics.KafkaCSVMetricsReporter",
    #"kafka.csv.metrics.dir" => "#{POSEIDON_PATH}/tmp/kafka_metrics",
    #"kafka.csv.metrics.reporter.enabled" => "false",
    "auto.create.topics.enable" => "true",

    # Trigger rebalances often to catch edge cases.
    "auto.leader.rebalance.enable" => "true",
    "leader.imbalance.check.interval.seconds" => 5
  }

  def initialize(id, port, partition_count = 1, replication_factor = 1, properties = {})
    @id   = id
    @port = port
    @log_dir = DEFAULT_PROPERTIES["log.dir"] + "_broker_#{id}"
    @jr = JavaRunner.new("broker_#{id}",
                         "#{ENV['KAFKA_PATH']}/bin/kafka-run-class.sh -name broker_#{id} kafka.Kafka",
                         "ps ax | grep -i 'kafka\.Kafka' | grep java | grep broker_#{id} | grep -v grep | awk '{print $1}'",
                         :sigterm,
                         DEFAULT_PROPERTIES.merge(
                           "broker.id" => id,
                           "port" => port,
                           "log.dir" => @log_dir,
                           "default.replication.factor" => replication_factor,
                           "num.partitions" => partition_count
                         ).merge(properties))
  end

  def start
    FileUtils.mkdir_p(@log_dir)
    @jr.start
  end

  def stop
    @jr.stop
  end

  def without_process
    @jr.without_process { yield }
  end
end


class ZookeeperRunner
  def initialize
    @data_dir = "#{POSEIDON_PATH}/tmp/zookeeper"

    @jr = JavaRunner.new("zookeeper",
                         "#{ENV['KAFKA_PATH']}/bin/zookeeper-server-start.sh",
                         "ps ax | grep -i 'zookeeper' | grep -v grep | awk '{print $1}'",
                         :sigkill,
                         :dataDir => @data_dir,
                         :clientPort => 2181,
                         :maxClientCnxns => 0)
  end

  def pid
    @jr.pid
  end

  def start
    FileUtils.mkdir_p(@data_dir)
    @jr.start
  end

  def stop
    @jr.stop
  end
end
