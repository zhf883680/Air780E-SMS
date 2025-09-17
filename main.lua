-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "smsdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require "sysplus" -- http库需要这个sysplus

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "Air780E sms forwarder")

--运营商给的dns经常抽风，手动指定
socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

-- 设置 SIM 自动恢复(单位: 毫秒), 搜索小区信息间隔(单位: 毫秒), 最大搜索时间(单位: 秒)
mobile.setAuto(1000 * 10)

-- 开启 IPv6
mobile.ipv6(true)

--缓存消息
local buff = {}
-- bark_url 不支持 TLSv1.3, 自建 Bark 服务端时，Nginx需要启用 TLSv1.2
bark_url = "https://api.day.app/push"
bark_key = "换成你自己的"
  
-- 辅助发送http Post 请求, 因为http库需要在task里运行
function http_post(url, headers, body)
    sys.taskInit(function()
        for i = 1, 10 do
            local code, headers, body = http.request("POST", url, headers, body).wait()
            log.info("resp", code)
            log.info("body", body)
            if code == 200 then
                break
            end
            sys.wait(5000)
        end
    end)
end

-- ================================================
-- 转发短信函数
-- ================================================
function forward_sms(num, txt)
    local body_tbl = {
        title = num,
        body = txt,
        device_key = bark_key,
        group = "SMS",
    }

    -- 判断短信内容是否包含“码”
    if txt:find("码", 1, true) then
        body_tbl.level = "active"
    else
        body_tbl.level = "passive"
    end

    local body = json.encode(body_tbl)
    local headers = {["Content-Type"] = "application/json"}
    log.info("json", body)
    http_post(bark_url, headers, body)
end

-- ================================================
-- 短信处理函数
-- ================================================
function sms_handler(num, txt)
    log.info("sms", num, txt)
    -- 固件已自动拼接长短信，直接转发
    forward_sms(num, txt)
end

-- ================================================
-- 订阅系统短信事件
-- ================================================
sys.subscribe("SMS_INC", function(phone, data)
    log.info("notify", "got sms", phone, data)
    table.insert(buff, {phone, data})
    sys.publish("SMS_ADD") -- 推送事件，唤醒 task
end)

-- ================================================
-- 短信处理任务循环
-- ================================================
sys.taskInit(function()
    while true do
        print("ww", collectgarbage("count"))
        while #buff > 0 do
            collectgarbage("collect") -- 防止内存不足
            local sms = table.remove(buff, 1)
            sms_handler(sms[1], sms[2])
        end
        log.info("notify", "wait for a new sms~")
        print("zzz", collectgarbage("count"))
        sys.waitUntil("SMS_ADD")
    end
end)



-------------------------------------------------------------------
-- 发送短信, 直接调用sms.send就行, 是不是task无所谓
-- sys.taskInit(function()
--     sys.wait(10000)
--     -- 中移动卡查短信
--     -- sms.send("+8610086", "301")
--     -- 联通卡查话费
--     sms.send("10010", "101")
-- end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
