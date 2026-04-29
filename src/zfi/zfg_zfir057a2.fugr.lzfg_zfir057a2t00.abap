*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZMV_ZFIR057AT2..................................*
TABLES: ZMV_ZFIR057AT2, *ZMV_ZFIR057AT2. "view work areas
CONTROLS: TCTRL_ZMV_ZFIR057AT2
TYPE TABLEVIEW USING SCREEN '9002'.
DATA: BEGIN OF STATUS_ZMV_ZFIR057AT2. "state vector
          INCLUDE STRUCTURE VIMSTATUS.
DATA: END OF STATUS_ZMV_ZFIR057AT2.
* Table for entries selected to show on screen
DATA: BEGIN OF ZMV_ZFIR057AT2_EXTRACT OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT2.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT2_EXTRACT.
* Table for all entries loaded from database
DATA: BEGIN OF ZMV_ZFIR057AT2_TOTAL OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT2.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT2_TOTAL.

*.........table declarations:.................................*
TABLES: ZFIR057AT2                     .
