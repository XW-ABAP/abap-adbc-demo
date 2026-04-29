*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZMV_ZFIR057AT3..................................*
TABLES: ZMV_ZFIR057AT3, *ZMV_ZFIR057AT3. "view work areas
CONTROLS: TCTRL_ZMV_ZFIR057AT3
TYPE TABLEVIEW USING SCREEN '9001'.
DATA: BEGIN OF STATUS_ZMV_ZFIR057AT3. "state vector
          INCLUDE STRUCTURE VIMSTATUS.
DATA: END OF STATUS_ZMV_ZFIR057AT3.
* Table for entries selected to show on screen
DATA: BEGIN OF ZMV_ZFIR057AT3_EXTRACT OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT3.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT3_EXTRACT.
* Table for all entries loaded from database
DATA: BEGIN OF ZMV_ZFIR057AT3_TOTAL OCCURS 0010.
INCLUDE STRUCTURE ZMV_ZFIR057AT3.
          INCLUDE STRUCTURE VIMFLAGTAB.
DATA: END OF ZMV_ZFIR057AT3_TOTAL.

*.........table declarations:.................................*
TABLES: ZFIR057AT3                     .
