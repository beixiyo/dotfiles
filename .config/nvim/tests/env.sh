# 根目录配置测试的现有插件依赖，在隔离子进程 HOME/工作目录前冻结
# vendor 内置依赖经 $VV_TEST_CONFIG_ROOT/vendors 自动发现；外部插件经原始 data site pack 发现
vv_test_dependency VV_ICONS vv-icons.nvim lua/vv-icons/init.lua
vv_test_dependency VV_BUFFERLINE vv-bufferline.nvim lua/vv-bufferline/init.lua
vv_test_dependency VV_TEST_FFF fff lua/fff.lua
vv_test_dependency VV_TEST_NOICE noice.nvim lua/noice/init.lua
vv_test_dependency VV_TEST_NUI nui.nvim lua/nui/popup/init.lua
vv_test_dependency VV_TEST_NOTIFY nvim-notify lua/notify/init.lua
