*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZMV_ZFIR057AT1..................................*
TABLES: ZMV_ZFIR057AT1, *ZMV_ZFIR057AT1. "view work areas
CONTROLS: TCTRL_ZMV_ZFIR057AT1
TYPE TABLEVIEW USING SCREEN '9001'.
DATA: BEGIN OF STATUS_ZMV_ZFIR057AT1. "state vector
          INCLUDE STRUCTURE VIMSTATUS.
DATA: END OF STATUS_ZMV_ZFIR057AT1.
* Table for entries selected to show on screen
DATA: BEGIN OF ZMV_ZFIR057AT1_EXTRACT OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT1.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT1_EXTRACT.
* Table for all entries loaded from database
DATA: BEGIN OF ZMV_ZFIR057AT1_TOTAL OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT1.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT1_TOTAL.

*.........table declarations:.................................*
TABLES: ZFIR057AT1                     .
