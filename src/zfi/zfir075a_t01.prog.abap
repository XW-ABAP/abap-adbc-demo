*&---------------------------------------------------------------------*
*& 包含               ZFIR057A_T01
*&---------------------------------------------------------------------*
TABLES:

  zfir057at1.


DATA:gt_zfir057at1 TYPE TABLE OF zfir057at1.
TYPES:ts_zfir057at1 TYPE zfir057at1.

TYPES: BEGIN OF ty_prog,
         progname TYPE zfir057at1-progname,
       END OF ty_prog.

TYPES: BEGIN OF ty_vari,
         variant TYPE zfir057at1-variant,
       END OF ty_vari.


SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  " 核心修改：在单选按钮组的其中一个添加 USER-COMMAND 触发屏幕事件
PARAMETERS: p_back TYPE c RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND rad, " 后台模式：自动全量推送
              p_fore TYPE c RADIOBUTTON GROUP g1.                             " 前台模式：弹窗人工勾选
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002. " 批量执行条件
  " 核心修改：给需要隐藏的字段加上 MODIF ID blk
SELECT-OPTIONS: s_repid FOR zfir057at1-progname MODIF ID blk NO INTERVALS NO-EXTENSION,  " 程序名范围
                  s_vari  FOR zfir057at1-variant  MODIF ID blk.  " 变式名范围
SELECTION-SCREEN END OF BLOCK b2.

*&---------------------------------------------------------------------*
*& 屏幕输出前事件 (PBO)
*&---------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
  PERFORM frm_adjust_screen.

*&---------------------------------------------------------------------*
*& Form frm_adjust_screen
*&---------------------------------------------------------------------*
FORM frm_adjust_screen .
  " 遍历当前选择屏幕的所有元素
  LOOP AT SCREEN.
    " 如果属于我们标记的 'BLK' 组
    IF screen-group1 = 'BLK'.
      IF p_back = 'X'.
        screen-active = '1'. " 显示该字段
      ELSE.
        screen-active = '0'. " 隐藏该字段（同时隐藏标签、输入框且不占用屏幕空间）
      ENDIF.
      " 必须执行 MODIFY 修改生效
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.
ENDFORM.


*&---------------------------------------------------------------------*
*& 自定义 F4 帮助事件 (LOW 和 HIGH 字段全覆盖)
*&---------------------------------------------------------------------*
" 程序名的 F4 (复用同一个 Form)

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_repid-low.
  PERFORM frm_f4_progname USING 'S_REPID-LOW'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_repid-high.
  PERFORM frm_f4_progname USING 'S_REPID-HIGH'.

  " 变式名的联动 F4 (传入 'L' 或 'H' 标识位 + 屏幕字段名)

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_vari-low.
  PERFORM frm_f4_variant USING 'L' 'S_VARI-LOW'.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR s_vari-high.
  PERFORM frm_f4_variant USING 'H' 'S_VARI-HIGH'.


*&---------------------------------------------------------------------*
*& Form frm_f4_progname (程序名通用 F4)
*&---------------------------------------------------------------------*
FORM frm_f4_progname USING pv_dynpro_field TYPE help_info-dynprofld.
  DATA: lt_prog   TYPE TABLE OF ty_prog,
        lt_return TYPE TABLE OF ddshretval.

  " 从配置表去重获取程序名
  SELECT DISTINCT progname
  INTO TABLE @lt_prog
  FROM zfir057at1.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'PROGNAME'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = pv_dynpro_field
      value_org       = 'S'
    TABLES
      value_tab       = lt_prog
      return_tab      = lt_return
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.
ENDFORM.

*&---------------------------------------------------------------------*
*& Form frm_f4_variant (变式名联动 F4 - 合并版)
*&---------------------------------------------------------------------*
FORM frm_f4_variant USING pv_mode         TYPE c " 'L'=LOW, 'H'=HIGH
                          pv_dynpro_field TYPE help_info-dynprofld.
  DATA: lt_vari   TYPE TABLE OF ty_vari,
        lt_return TYPE TABLE OF ddshretval.

  DATA: lt_dynp     TYPE TABLE OF dynpread,
        ls_dynp     TYPE dynpread,
        lv_progname TYPE zfir057at1-progname.

  " 1. 一次性把屏幕上的 LOW 和 HIGH 都抓取下来
  CLEAR: lt_dynp.
  ls_dynp-fieldname = 'S_REPID-LOW'.
  APPEND ls_dynp TO lt_dynp.
  ls_dynp-fieldname = 'S_REPID-HIGH'.
  APPEND ls_dynp TO lt_dynp.

  CALL FUNCTION 'DYNP_VALUES_READ'
    EXPORTING
      dyname     = sy-repid
      dynumb     = sy-dynnr
    TABLES
      dynpfields = lt_dynp
    EXCEPTIONS
      OTHERS     = 1.

  IF sy-subrc = 0.
    " 2. 根据传入的模式 (pv_mode) 决定取值逻辑
    IF pv_mode = 'H'.
      " HIGH 模式：优先取 HIGH，没有填再取 LOW
      READ TABLE lt_dynp INTO ls_dynp WITH KEY fieldname = 'S_REPID-HIGH'.
      IF ls_dynp-fieldvalue IS NOT INITIAL.
        lv_progname = ls_dynp-fieldvalue.
      ELSE.
        READ TABLE lt_dynp INTO ls_dynp WITH KEY fieldname = 'S_REPID-LOW'.
        lv_progname = ls_dynp-fieldvalue.
      ENDIF.
    ELSE.
      " LOW 模式：直接取 LOW
      READ TABLE lt_dynp INTO ls_dynp WITH KEY fieldname = 'S_REPID-LOW'.
      lv_progname = ls_dynp-fieldvalue.
    ENDIF.

    " 转换大写
    TRANSLATE lv_progname TO UPPER CASE.
  ENDIF.

  " 3. 根据抓取到的程序名过滤变式
  IF lv_progname IS NOT INITIAL.
    SELECT DISTINCT variant
      INTO TABLE @lt_vari
    FROM zfir057at1
    WHERE progname = @lv_progname.
  ELSE.
    " 没抓到程序名则带出所有变式
    SELECT DISTINCT variant
    INTO TABLE @lt_vari
    FROM zfir057at1.
  ENDIF.

  " 4. 弹出联动结果
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      retfield        = 'VARIANT'
      dynpprog        = sy-repid
      dynpnr          = sy-dynnr
      dynprofield     = pv_dynpro_field
      value_org       = 'S'
    TABLES
      value_tab       = lt_vari
      return_tab      = lt_return
    EXCEPTIONS
      parameter_error = 1
      no_values_found = 2
      OTHERS          = 3.
ENDFORM.