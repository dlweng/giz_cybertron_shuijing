window.apiConfig = {
    isDebug:false,
    isBeta:true,
    proxyUrl: 'beApi/',
    gizwitsEnterpriseId: '2ebb7771f6154016a488a397e5927343',
    gizwitsEnterpriseSecrets: '95c384b4d2ac4d5794c8c648bce0848d',
    wxAppid: 'wx53e64588c34f3653',
    url: "http://dev.dev.applehater.cn/",
    //url: "http://water.gizwits.com/",
    api: {
        getOpenid:"oauth2/getOpenid", //获取微信用户openid
        getToken:"oauth2/token", //获取机智云token
        jsApiTicket:"oauth2/ticket", //获取授权调用jsapi_ticket的参数       
        deviceOper:"device/act/" //与设备相关的操作
    },
    wsUrl: "ws://m2m.gizwits.com:8080/ws/app/v1", //websocket地址
    heartBeat: 15, //心跳间隔时间
    jzAppId: "3424873405b74e778d47ddc8225513e7", //6140e6a3d8174b6eb360417603a1eaf4 机智云AppId(应用)
    jzUrl: "api.gizwits.com", //机智云接口URL
    jzPKey: [
        "d62bb95a8ca443288215eca411fced6f" //机智云净水器KEY
    ],
    jzPSecret: [
        "73fb4d623040432690b5bf0fb09dff11" //机智云净水器_密钥
    ],
    jzApi: {
        Login: "app/users", //机智云-登录
        Bindings: "app/bindings", //机智云-用户绑定的设备列表
        BindMac: "app/bind_mac", //机智云-用户绑定设备
        GetDevdata: "app/devdata/", //机智云-获取设备最近上传数据
        Control: "app/control/" //机智云-设置数据点-远程控制设备
    }
};