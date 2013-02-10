require 'open3'

Config = {
  :dests => [],
  :srcs => [],
  :servername => [],
  :passphrase => ""
}

class Destination
  # The url/path for duplicity
  def duplicityURL
    nil
  end
  
  # Additional options for duplicity
  def duplicityOptions
    []
  end
  
  # Additional env for duplicity
  def duplicityENV
    {}
  end
  
  def prettyName
    nil
  end
end

class DestinationS3 < Destination
  @bucket_name
  @keyID
  @key
  
  def bucket(bucket_name)
    @bucket_name = bucket_name
  end
  
  def accessKey(keyID, key)
    @keyID = keyID
    @key = key
  end
  
  def duplicityENV
    env = {}
    env["AWS_ACCESS_KEY_ID"] = @keyID
    env["AWS_SECRET_ACCESS_KEY"] = @key
    
    super.merge env
  end
  
  def prettyName
    "s3:#{@bucket_name}"
  end
  
  def duplicityURL
    "s3+http://#{@bucket_name}/#{Config[:servername].downcase}"
  end
  
  def duplicityOptions
    options = [
      "--s3-use-new-style"
    ]
    
    super << options
  end
end

class Source
  @src
  
  def initialize(src)
    @src = src
  end
  
  def prettyName
    @src
  end
  
  # The url/path for duplicity
  def duplicityURL
    nil
  end
  
  # Additional options for duplicity
  def duplicityOptions
    []
  end
  
  # Additional env for duplicity
  def duplicityENV
    {}
  end
  
  # Run before the backup
  def pre
  end
  
  # Run after the backup
  def post
  end
  
  # A shot name for the dest
  def destName
    @src
  end
end

class SourceDir < Source
  
  def duplicityURL
    @src
  end
  
  def destName
    File.basename(@src)
  end
end

# class SourceMysql < Source
#   def prettyName
#     "mysql:#{@src}"
#   end
#   
#   def destName
#     "mysql-#{@src}"
#   end
# end

def set(key, value)  
  Config[key] = value
end

def dest(type, &block)
  destination = Object.const_get("Destination" + type.to_s().capitalize).new
  
  block.arity < 1 ? destination.instance_eval(&block) : block.call(source) if block_given?
  
  Config[:dests] << destination
end

def src(type, src, &block)
  source = Object.const_get("Source" + type.to_s().capitalize).new(src)
  
  block.arity < 1 ? source.instance_eval(&block) : block.call(source) if block_given?
  
  Config[:srcs] << source
end

load 'config.conf',true


class ServerBackup
  def initialize
    @failed = {}
  end
  
  def run
    Config[:srcs].each do |src|
      runFor(src)
    end
    
    puts
    if @failed.size > 0 
      puts 'During backups a error did occour:'
      
      @failed.each do |name, log|
        puts "#{name} failed:"
        puts log
        puts
      end
      
      exit 1
    else
      puts 'Everything succeded =)'
      
      exit 0
    end
  end
  
  def runFor(src)
    puts "Backup #{src.prettyName}"
    src.pre
    Config[:dests].each do |dest|
      print " -> #{dest.prettyName}..."
      ok, log = runDuplicity(src, dest)
      
      if ok
        puts "ok."
      else
        @failed["#{src.prettyName}->#{dest.prettyName}"] = log
        puts "failed."
      end
    end
    src.post
  end
  
  def runDuplicity(src, dest)
    env = {
      'PASSPHRASE' => Config[:passphrase]
    }
    
    env.update dest.duplicityENV
    env.update src.duplicityENV
    
    options = []
    
    options << dest.duplicityOptions
    options << src.duplicityOptions
    options << src.duplicityURL
    options << File.join(dest.duplicityURL, src.destName)
  
    cmd = ["duplicity", *options].join " "
    
    exit_status = 0
    log = nil

    Open3.popen2e(env, cmd) { |stdin, stdout_stderr, wait_thr|
      exit_status = wait_thr.value
      
      if exit_status != 0
        log = stdout_stderr.readlines()
      end
    }
    
    return exit_status == 0, log
  end
end

ServerBackup.new.run
