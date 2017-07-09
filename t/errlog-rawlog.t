# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

log_level('error');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 2 + 4);

my $pwd = cwd();

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config || '';
    my $init_by_lua_block = $block->init_by_lua_block || 'require "resty.core"';

    $http_config .= <<_EOC_;

    lua_package_path "$pwd/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";
    init_by_lua_block {
        $init_by_lua_block
        local errlog_file = "$Test::Nginx::Util::ErrLogFile"
    }
_EOC_

    $block->set_value("http_config", $http_config);
});

no_long_string();
run_tests();

__DATA__

=== TEST 1: errlog.rawlog with bad log level (ngx.ERROR, -1)
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"

            errlog.rawlog(ngx.ERROR, "hello, log")
            ngx.say("done")
        }
    }
--- request
GET /log
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad log level: -1



=== TEST 2: errlog.rawlog with bad levels (9)
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"

            errlog.rawlog(9, "hello, log")
            ngx.say("done")
        }
    }
--- request
GET /log
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad log level: 9



=== TEST 3: errlog.rawlog with bad log message
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"

            errlog.rawlog(ngx.ERR, 123)
            ngx.say("done")
        }
    }
--- request
GET /log
--- response_body_like: 500 Internal Server Error
--- error_code: 500
--- error_log
bad argument #2 to 'rawlog' (must be a string)



=== TEST 4: errlog.rawlog test log-level ERR
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"

            errlog.rawlog(ngx.ERR, "hello world")
        }
    }
--- request
GET /log
--- error_log eval
qr/\[error\] \S+: \S+ hello world/



=== TEST 5: errlog.rawlog JITs
--- init_by_lua_block
    -- local verbose = true
    local verbose = false
    local outfile = errlog_file
    -- local outfile = "/tmp/v.log"
    if verbose then
        local dump = require "jit.dump"
        dump.on(nil, outfile)
    else
        local v = require "jit.v"
        v.on(outfile)
    end

    require "resty.core"
    -- jit.opt.start("hotloop=1")
    -- jit.opt.start("loopunroll=1000000")
    -- jit.off()
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"

            for i = 1, 100 do
                errlog.rawlog(ngx.ERR, "hello world")
            end
        }
    }
--- request
GET /log
--- error_log eval
qr/\[TRACE   \d+ content_by_lua\(nginx.conf:\d+\):4 loop\]/



=== TEST 6: errlog.rawlog in init_by_lua
--- init_by_lua_block
    local errlog = require "ngx.errlog"
    errlog.rawlog(ngx.ERR, "hello world from init_by_lua")
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- grep_error_log chop
hello world from init_by_lua
--- grep_error_log_out eval
["hello world from init_by_lua\n", ""]



=== TEST 7: errlog.rawlog in init_worker_by_lua
--- http_config
    init_worker_by_lua_block {
        local errlog = require "ngx.errlog"
        errlog.rawlog(ngx.ERR, "hello world from init_worker_by_lua")
    }
--- config
    location /t {
        return 200;
    }
--- request
GET /t
--- grep_error_log chop
hello world from init_worker_by_lua
--- grep_error_log_out eval
["hello world from init_worker_by_lua\n", ""]



=== TEST 8: errlog.rawlog with \0 in the log message
--- config
    location /log {
        content_by_lua_block {
            local errlog = require "ngx.errlog"
            errlog.rawlog(ngx.ERR, "hello\0world")
            ngx.say("ok")
        }
    }
--- request
GET /log
--- response_body
ok
--- error_log eval
"hello\0world, client: "
