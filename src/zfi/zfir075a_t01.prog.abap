*&---------------------------------------------------------------------*
*& 包含               ZFIR057A_T01
*&---------------------------------------------------------------------*
TABLES:

  zfir057at1.


DATA:gt_zfir057at1 TYPE TABLE OF zfir057at1.
TYPES:ts_zfir057at1 TYPE zfir057at1.



*&---------------------------------------------------------------------*
*& 选择屏幕 (控制前后台运行模式)
*&---------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_back TYPE c RADIOBUTTON GROUP g1 DEFAULT 'X', " 后台模式：自动全量推送
              p_fore TYPE c RADIOBUTTON GROUP g1.             " 前台模式：弹窗人工勾选
SELECTION-SCREEN END OF BLOCK b1.
