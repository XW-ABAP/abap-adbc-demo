*&---------------------------------------------------------------------*
*& Include           ZFIR057A_T01
*&---------------------------------------------------------------------*
TABLES:
  zfir057at1.

DATA: gt_zfir057at1 TYPE TABLE OF zfir057at1.
TYPES: ts_zfir057at1 TYPE zfir057at1.

*&---------------------------------------------------------------------*
*& Selection Screen (Execution Mode Control: Background vs. Foreground)
*&---------------------------------------------------------------------*
" Note: Ensure TEXT-001 is defined in your Text Elements as "Execution Mode Settings"
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: 
    p_back TYPE c RADIOBUTTON GROUP g1 DEFAULT 'X', " Background: Automatic Full Data Push
    p_fore TYPE c RADIOBUTTON GROUP g1.             " Foreground: Manual Selection via Popup
SELECTION-SCREEN END OF BLOCK b1.