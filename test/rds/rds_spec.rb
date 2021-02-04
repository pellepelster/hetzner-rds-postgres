require 'spec_helper'
require 'securerandom'
require 'ipaddr'
require 'faraday'
require 'timeout'
require 'net/http'
require 'pg'
require 'rubygems'
require 'net/http'
require 'test_utils'

describe 'hetzner-rds-postgres' do

  # snippet:test_volume_helper
  def remove_data_volume
    `docker volume rm -f rds_rds-data`
  end

  def remove_backup_volume
    `docker volume rm -f rds_rds-backup`
  end
  # /snippet:test_volume_helper

  def wait_for_server_start(service)
    wait_while {
      !@compose.logs(service).include? 'database system is ready to accept connections'
    }

    host, port = @compose.address(service, 5432)
    wait_while {
      !is_port_open?(host, port)
    }

    sleep 5
  end

  def clean_start(service)
    @compose.force_shutdown

    remove_data_volume
    remove_backup_volume

    @compose.up(service, detached: true)
    host, port = @compose.address(service, 5432)

    wait_while {
      !@compose.logs(service).include? 'backup command end: completed successfully'
    }

    wait_while {
      !is_port_open?(host, port)
    }

    return host, port
  end

  before(:all) do
    @compose ||= ComposeWrapper.new('rds/docker-compose.yml')
  end

  after(:all) do
    #@compose.dump_logs
    @compose.force_shutdown
  end

  it 'can connect with user test1 to database test1' do
    @compose.up('rds-test1-no-instance-id', detached: true)

    wait_while {
      !@compose.logs('rds-test1-no-instance-id').include? 'DB_INSTANCE_ID not set or empty, exiting'
    }
  end

  it 'can connect with user test1 to database test1' do
    host, port = clean_start('rds-test1')
    conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', 'password1')
    conn.exec('SELECT version();')
    conn.close
  end

  it "does not allow empty passwords" do
    err = assert_raises PG::ConnectionBad do

      host, port = clean_start('rds-test1-no-password')
      conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', ' ')
      conn.exec('SELECT version();')
      conn.close
    end
  end

  it 'does not allow empty passwords' do
  end

  it 'keeps data after restart' do
    host, port = clean_start('rds-test1')
    conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', 'password1')

    conn.exec('CREATE TABLE pets (id SERIAL PRIMARY KEY, name VARCHAR(64) NOT NULL);')

    petname = SecureRandom.uuid
    conn.exec("INSERT INTO pets (name) VALUES ('#{petname}');")

    pets = conn.exec("SELECT * FROM pets;").map { |row| row['name'] }
    assert_includes(pets, petname)
    conn.close

    @compose.kill('rds-test1')
    wait_while {
      !@compose.logs('rds-test1').include? 'database system is shut down'
    }
    @compose.rm('rds-test1', force: true)
    @compose.up('rds-test1', detached: true)

    host, port = @compose.address('rds-test1', 5432)
    wait_for_server_start('rds-test1')

    conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', 'password1')
    pets = conn.exec("SELECT * FROM pets;").map { |row| row['name'] }
    assert_includes(pets, petname)
  end

  it 'restores latest data from backup' do
    # snippet:test_restore_setup
    host, port = clean_start('rds-test1')
    conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', 'password1')

    conn.exec('CREATE TABLE pets (id SERIAL PRIMARY KEY, name VARCHAR(64) NOT NULL);')

    petname = SecureRandom.uuid
    conn.exec("INSERT INTO pets (name) VALUES ('#{petname}');")

    pets = conn.exec("SELECT * FROM pets;").map { |row| row['name'] }
    assert_includes(pets, petname)
    conn.close
    # /snippet:test_restore_setup

    # snippet:test_restore_destroy
    @compose.exec('rds-test1', '/rds/bin/backup.sh')

    # stopping instance and remove data volume
    @compose.kill('rds-test1')
    wait_while {
      !@compose.logs('rds-test1').include? 'database system is shut down'
    }
    @compose.rm('rds-test1', force: true)
    remove_data_volume
    # /snippet:test_restore_destroy

    # snippet:test_restore_verify
    @compose.up('rds-test1', detached: true)


    host, port = @compose.address('rds-test1', 5432)
    wait_for_server_start('rds-test1')

    conn = PG::Connection.new(host, port, '', '', 'test1', 'test1', 'password1')
    pets = conn.exec("SELECT * FROM pets;").map { |row| row['name'] }
    assert_includes(pets, petname)
    # /snippet:test_restore_verify

  end
end