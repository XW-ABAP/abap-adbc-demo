*&---------------------------------------------------------------------*
*& Report ZFIR057A
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zfir075a.

INCLUDE zfir075a_t01.

INCLUDE zfir075a_frm.



START-OF-SELECTION.
  IF p_back = 'X'.
    PERFORM frm_getdata_push.
  ELSEIF p_fore = 'X'.
    PERFORM frm_fore_select_config.
  ENDIF.
