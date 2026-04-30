*&---------------------------------------------------------------------*
*& Include ZFIR057A_FRM
*&---------------------------------------------------------------------*

FORM frm_getdata_push.

  " --- 1. Data Declaration Section ---
  DATA: lr_data         TYPE REF TO data.
  DATA: lv_submit_prog TYPE program,
        lv_submit_vari TYPE variant.

  " RTTS (Run-Time Type Services) Description Objects
  DATA: lo_table_descr  TYPE REF TO cl_abap_tabledescr,
        lo_struct_descr TYPE REF TO cl_abap_structdescr,
        lt_components   TYPE cl_abap_structdescr=>component_table,
        ls_component    LIKE LINE OF lt_components.

  FIELD-SYMBOLS: <lt_alv_data> TYPE STANDARD TABLE,
                 <ls_row>      TYPE any,
                 <lv_value>    TYPE any.

  " --- 2. Fetch Configuration Table Data ---
  IF p_back = 'X'.
    " Background Mode: Fetch all active configurations
    SELECT * FROM zfir057at1
       INTO CORRESPONDING FIELDS OF TABLE gt_zfir057at1
       WHERE zblock_push = ''.
  ELSE.
    " Logic for other modes if applicable
  ENDIF.

  SELECT * FROM zfir057at2
    INTO TABLE @DATA(lt_zfir057at2).

  IF sy-subrc = 0.
    SORT lt_zfir057at2 BY progname variant.
  ENDIF.

  " Predefined Mapping Internal Table
  DATA: lt_mapping LIKE lt_zfir057at2.

  " --- 3. Process Each ALV Program via Loop ---
  LOOP AT gt_zfir057at1 INTO DATA(ls_zfir057at1).

    " Reset key pointers and variables for each iteration
    CLEAR: lv_submit_prog, lv_submit_vari, lt_mapping.
    IF <lt_alv_data> IS ASSIGNED.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    lv_submit_prog = to_upper( condense( ls_zfir057at1-progname ) ).
    lv_submit_vari = to_upper( condense( ls_zfir057at1-variant ) ).

    IF lv_submit_prog IS INITIAL. CONTINUE. ENDIF.

    " --- 4. Set Runtime Parameters and Execute ---
    cl_salv_bs_runtime_info=>clear( ).
    cl_salv_bs_runtime_info=>set(
      EXPORTING
        display  = abap_false
        metadata = abap_false
        data     = abap_true
    ).

    " Execute target program and return
    SUBMIT (lv_submit_prog) USING SELECTION-SET lv_submit_vari AND RETURN.

    " --- 5. Retrieve Data from Memory ---
    TRY.
        cl_salv_bs_runtime_info=>get_data_ref( IMPORTING r_data = lr_data ).
        ASSIGN lr_data->* TO <lt_alv_data>.
      CATCH cx_salv_bs_sc_runtime_info.
        WRITE: / 'Warning: Program', lv_submit_prog, 'did not return ALV data'.
        cl_salv_bs_runtime_info=>clear( ).
        CONTINUE.
    ENDTRY.

    " --- 6. Handle Output Logic ---
    IF <lt_alv_data> IS ASSIGNED AND <lt_alv_data> IS NOT INITIAL.

      " Extract field mappings for the current program
      lt_mapping = VALUE #( FOR ls_m IN lt_zfir057at2
                             WHERE ( progname = lv_submit_prog AND variant = lv_submit_vari )
                             ( ls_m ) ).

      WRITE: / '-------------------------------------------'.
      WRITE: / 'Executing Program:', lv_submit_prog, ' Variant:', lv_submit_vari.

      TRY.
          " Use RTTS to describe the dynamic structure
          lo_table_descr ?= cl_abap_tabledescr=>describe_by_data( <lt_alv_data> ).
          lo_struct_descr ?= lo_table_descr->get_table_line_type( ).
          lt_components = lo_struct_descr->get_components( ).

          LOOP AT lt_components INTO DATA(ls_comp).
            " Filter out complex fields: Internal Tables, Nested Structures, References
            IF ls_comp-type->type_kind = 'h' OR   " Internal Table
               ls_comp-type->type_kind = 's' OR   " Flat Structure (handled as single unit)
               ls_comp-type->type_kind = 'u' OR   " Deep Structure
               ls_comp-type->type_kind = 'v' OR   " Data Reference
               ls_comp-type->type_kind = 'l'.     " Object Reference

              DELETE TABLE lt_components FROM ls_comp.
              CONTINUE.
            ENDIF.

            " Note: 
            " 'g' (String) maps to VARCHAR(MAX)
            " 'y' (XString) maps to VARBINARY
            " 's' (Flat Structure) needs flattening or removal for DB tables.
          ENDLOOP.

          cl_salv_bs_runtime_info=>clear( ).

          " Optional Metadata Display
          IF ls_zfir057at1-zsfshowfield = 'X'.
            IF sy-mandt = '600' OR sy-mandt = '800'.
              " Restricted Clients logic
            ELSE.
              " 1. Define intermediate structure for ALV metadata display
              TYPES: BEGIN OF ty_comp_output,
                       name          TYPE abap_compname,    " Field Name
                       type_kind     TYPE abap_typekind,    " Type Kind
                       length        TYPE i,                " Length
                       decimals      TYPE i,                " Decimals
                       absolute_name TYPE string,           " Reference Dict Type
                     END OF ty_comp_output.
              DATA: lt_comp_output TYPE TABLE OF ty_comp_output.

              " 2. Extract metadata into the display table
              LOOP AT lt_components INTO ls_comp.
                APPEND INITIAL LINE TO lt_comp_output ASSIGNING FIELD-SYMBOL(<ls_out>).
                <ls_out>-name      = ls_comp-name.
                <ls_out>-type_kind = ls_comp-type->type_kind.
                <ls_out>-length    = ls_comp-type->length.
                <ls_out>-decimals  = ls_comp-type->decimals.

                " Clean the absolute path name
                <ls_out>-absolute_name = ls_comp-type->absolute_name.
                REPLACE FIRST OCCURRENCE OF '\TYPE=' IN <ls_out>-absolute_name WITH ''.
                REPLACE FIRST OCCURRENCE OF '\DATA=' IN <ls_out>-absolute_name WITH ''.
              ENDLOOP.

              " 3. Call SALV Factory for Popup Display
              DATA: lo_alv_comp TYPE REF TO cl_salv_table.
              TRY.
                  cl_salv_table=>factory(
                    IMPORTING r_salv_table = lo_alv_comp
                    CHANGING  t_table      = lt_comp_output ).

                  lo_alv_comp->set_screen_popup(
                    start_column = 10 end_column = 150 start_line = 5 end_line = 20 ).

                  lo_alv_comp->get_functions( )->set_all( abap_true ).

                  " Set Column Headers
                  DATA(lo_cols) = lo_alv_comp->get_columns( ).
                  lo_cols->set_optimize( abap_true ).
                  lo_cols->get_column( 'NAME' )->set_short_text( 'Field' ).
                  lo_cols->get_column( 'TYPE_KIND' )->set_short_text( 'Type' ).
                  lo_cols->get_column( 'LENGTH' )->set_short_text( 'Len(B)' ).
                  lo_cols->get_column( 'DECIMALS' )->set_short_text( 'Dec' ).
                  lo_cols->get_column( 'ABSOLUTE_NAME' )->set_short_text( 'Ref Dict' ).

                  lo_alv_comp->display( ).

                CATCH cx_salv_msg.
                  MESSAGE 'Failed to display metadata popup' TYPE 'E'.
              ENDTRY.
            ENDIF.
          ENDIF.
        CATCH cx_root.
          WRITE: / 'Error: Dynamic structure analysis failed'.
      ENDTRY.

      " --- 7. Inject System Fields (ID, YEAR, MONTH) ---
      DATA: lo_elem_id    TYPE REF TO cl_abap_elemdescr,
            lo_elem_year  TYPE REF TO cl_abap_elemdescr,
            lo_elem_month TYPE REF TO cl_abap_elemdescr.

      lo_elem_id = cl_abap_elemdescr=>get_c( 32 ). " UUID C32

      IF ls_zfir057at1-zsfyearmonth = 'X'.
        lo_elem_year  = cl_abap_elemdescr=>get_c( 4 ).
        lo_elem_month = cl_abap_elemdescr=>get_c( 2 ).
      ENDIF.

      " Insert at the beginning of the component table
      INSERT VALUE #( name = 'ID'    type = lo_elem_id )    INTO lt_components INDEX 1.
      IF ls_zfir057at1-zsfyearmonth = 'X'.
        INSERT VALUE #( name = 'YEAR'  type = lo_elem_year )  INTO lt_components INDEX 2.
        INSERT VALUE #( name = 'MONTH' type = lo_elem_month ) INTO lt_components INDEX 3.
      ENDIF.

      " --- 8. Apply Field Mapping and Filtering ---
      IF lt_mapping IS NOT INITIAL.
        SORT lt_mapping BY sapfield.
        LOOP AT lt_components ASSIGNING FIELD-SYMBOL(<fs_component>).
          " Skip primary key fields from mapping logic
          IF <fs_component>-name = 'ID' OR <fs_component>-name = 'YEAR' OR <fs_component>-name = 'MONTH'.
            CONTINUE.
          ENDIF.

          " Find mapping in config table
          READ TABLE lt_mapping INTO DATA(ls_mapping) WITH KEY sapfield = <fs_component>-name BINARY SEARCH.
          IF sy-subrc <> 0.
            " If no mapping exists, exclude from sync
            DELETE TABLE lt_components FROM <fs_component>.
            CONTINUE.
          ENDIF.

          " Rename field if configured
          IF ls_mapping-zreplacefield = 'X'.
            <fs_component>-name = ls_mapping-non_sapfield.
          ENDIF.
        ENDLOOP.

        WRITE: / 'Output Mode: Partial Field Mapping'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1.
      ELSE.
        WRITE: / 'Output Mode: Full Field Automatic Output'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1.
      ENDIF.

      " --- Cleanup per loop iteration ---
      REFRESH lt_mapping.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    cl_salv_bs_runtime_info=>clear( ).
  ENDLOOP.

ENDFORM.

" ---------------------------------------------------------------------
" FORM frm_crud_targetdata
" Handle DB connection and data sync (Delete then Insert)
" ---------------------------------------------------------------------
FORM frm_crud_targetdata TABLES lt_components TYPE cl_abap_structdescr=>component_table
                                pt_table      TYPE STANDARD TABLE
                          USING ps_zfir057at1   TYPE ts_zfir057at1.

  DATA: lv_target_tbname TYPE tabname.
  DATA: lt_val_tab TYPE TABLE OF rsparams.
  DATA: lv_where TYPE string.
  DATA: lt_shdb_seltables TYPE cl_shdb_seltab=>tt_named_seltables,
        ls_shdb_seltables LIKE LINE OF lt_shdb_seltables.
  DATA: lt_where_clauses TYPE TABLE OF string.

  IF ps_zfir057at1-tabname IS NOT INITIAL.
    lv_target_tbname = condense( ps_zfir057at1-tabname ).
  ENDIF.

  " Get Selection Criteria for WHERE clause
  SELECT * FROM zfir057at3
    INTO TABLE @DATA(lt_zfir057at3)
    WHERE progname = @ps_zfir057at1-progname
      AND variant  = @ps_zfir057at1-variant.

  IF sy-subrc = 0.
    SORT lt_zfir057at3 BY sapfield.
    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report  = ps_zfir057at1-progname
        variant = ps_zfir057at1-variant
      TABLES
        valutab = lt_val_tab
      EXCEPTIONS
        OTHERS  = 3.

    LOOP AT lt_val_tab INTO DATA(ls_val_tab).
      READ TABLE lt_zfir057at3 INTO DATA(ls_zfir057at3) WITH KEY sapfield = ls_val_tab-selname BINARY SEARCH.
      IF sy-subrc <> 0 OR ( ls_val_tab-low IS INITIAL AND ls_val_tab-high IS INITIAL ).
        DELETE TABLE lt_val_tab FROM ls_val_tab.
        CONTINUE.
      ENDIF.

      " Handle Data Conversion (Leading Zeros)
      IF ls_zfir057at3-reffiled IS NOT INITIAL.
        DATA: lr_ref_data TYPE REF TO data.
        TRY.
            CREATE DATA lr_ref_data TYPE (ls_zfir057at3-reffiled).
            FIELD-SYMBOLS: <lv_ref_val> TYPE any.
            ASSIGN lr_ref_data->* TO <lv_ref_val>.
            DESCRIBE FIELD <lv_ref_val> LENGTH DATA(lv_len) IN CHARACTER MODE.

            IF ls_val_tab-low IS NOT INITIAL.
              DATA(lv_low_clean) = condense( ls_val_tab-low ).
              IF ls_zfir057at3-sapconv = 'I'. " Input: Add leading zeros
                ls_val_tab-low = |{ lv_low_clean WIDTH = lv_len ALIGN = RIGHT PAD = '0' }|.
              ELSEIF ls_zfir057at3-sapconv = 'O'. " Output: Remove leading zeros
                SHIFT lv_low_clean LEFT DELETING LEADING '0'.
                ls_val_tab-low = lv_low_clean.
              ENDIF.
            ENDIF.
            " ... Repeat for HIGH value ...
          CATCH cx_sy_create_data_error.
        ENDTRY.
      ENDIF.

      " Build WHERE Clause
      IF ls_val_tab-kind = 'P'.
        APPEND |{ ls_zfir057at3-dbfield } = '{ ls_val_tab-low }'| TO lt_where_clauses.
      ELSEIF ls_val_tab-kind = 'S'.
        " Using cl_shdb_seltab to convert Range to SQL WHERE
        TYPES: tt_range_string TYPE RANGE OF string.
        ls_shdb_seltables-name = ls_zfir057at3-dbfield.
        DATA: lr_range_table TYPE REF TO data.
        CREATE DATA lr_range_table TYPE tt_range_string.
        FIELD-SYMBOLS: <lt_range> TYPE tt_range_string.
        ASSIGN lr_range_table->* TO <lt_range>.
        APPEND VALUE #( sign = ls_val_tab-sign option = ls_val_tab-option 
                        low = ls_val_tab-low high = ls_val_tab-high ) TO <lt_range>.
        ls_shdb_seltables-dref = lr_range_table.
        APPEND ls_shdb_seltables TO lt_shdb_seltables.
        DATA(lv_s_where) = cl_shdb_seltab=>combine_seltabs( it_named_seltabs = lt_shdb_seltables ).
        APPEND lv_s_where TO lt_where_clauses.
        CLEAR: lt_shdb_seltables, lv_s_where.
      ENDIF.
    ENDLOOP.
  ENDIF.

  " Add Time-based filters
  IF ps_zfir057at1-zsfyearmonth = 'X'.
    APPEND | YEAR = '{ sy-datum+0(4) }'| TO lt_where_clauses.
    APPEND | MONTH = '{ sy-datum+4(2) }'| TO lt_where_clauses.
  ENDIF.

  lv_where = concat_lines_of( table = lt_where_clauses sep = ' AND ' ).

  " --- Dynamic Table Generation for External DB ---
  DATA: lo_new_struct_descr TYPE REF TO cl_abap_structdescr,
        lo_new_table_descr  TYPE REF TO cl_abap_tabledescr,
        lr_db_data          TYPE REF TO data.
  FIELD-SYMBOLS: <lt_db> TYPE STANDARD TABLE.

  TRY.
      lo_new_struct_descr = cl_abap_structdescr=>create( p_components = lt_components[] ).
      lo_new_table_descr  = cl_abap_tabledescr=>create( p_line_type = lo_new_struct_descr ).
      CREATE DATA lr_db_data TYPE HANDLE lo_new_table_descr.
      ASSIGN lr_db_data->* TO <lt_db>.
    CATCH cx_root INTO DATA(lx_rtts_err).
      WRITE: / 'Dynamic table generation failed:', lx_rtts_err->get_text( ).
      RETURN.
  ENDTRY.

  " --- ADBC: Native SQL Execution ---
  DATA: go_db TYPE REF TO cl_sql_connection,
        go_sqlerr_ref TYPE REF TO cx_sql_exception.

  TRY.
      go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).
      
      " 1. Batch Delete existing data based on WHERE criteria
      IF lv_target_tbname IS NOT INITIAL AND lv_where IS NOT INITIAL.
        DATA(lv_stmt_del) = |DELETE FROM { lv_target_tbname } WHERE { lv_where }|.
        DATA(lo_stmt_del) = go_db->create_statement( ).
        DATA(lv_deleted) = lo_stmt_del->execute_update( lv_stmt_del ).
        go_db->commit( ).
        WRITE: / 'Batch delete successful. Rows affected:', lv_deleted.
      ENDIF.

      " 2. Batch Insert new data
      IF pt_table[] IS NOT INITIAL.
        " Map ALV data to dynamic DB structure
        " (Loop and mapping logic here...)
        
        DATA(lo_stmt_ins) = go_db->create_statement( ).
        lo_stmt_ins->set_param_table( lr_db_data ).
        " ... dynamic INSERT SQL assembly ...
        DATA(lv_inserted) = lo_stmt_ins->execute_update( lv_insert_sql ).
        go_db->commit( ).
        WRITE: / 'Write successful. Records:', lv_inserted.
      ENDIF.

    CATCH cx_sql_exception INTO go_sqlerr_ref.
      IF go_db IS NOT INITIAL. go_db->rollback( ). ENDIF.
      MESSAGE go_sqlerr_ref->sql_message TYPE 'E'.
  ENDTRY.

ENDFORM.

" ---------------------------------------------------------------------
" FORM frm_fore_select_config
" UI Popup for user selection of synchronization tasks
" ---------------------------------------------------------------------
FORM frm_fore_select_config.
  DATA: lt_config TYPE TABLE OF zfir057at1,
        lo_alv    TYPE REF TO cl_salv_table.

  SELECT * FROM zfir057at1 INTO TABLE @lt_config WHERE zblock_push = ''.
  IF sy-subrc <> 0.
    MESSAGE 'No active configuration found!' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  TRY.
      cl_salv_table=>factory( IMPORTING r_salv_table = lo_alv CHANGING t_table = lt_config ).
      lo_alv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>multiple ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->set_screen_popup( start_column = 10 end_column = 120 start_line = 5 end_line = 20 ).

      WRITE: / '>> Waiting for user to select tasks in Console...'.
      lo_alv->display( ).

      DATA(lt_sel_rows) = lo_alv->get_selections( )->get_selected_rows( ).
      IF lt_sel_rows IS INITIAL.
        WRITE: / '>> No tasks selected. Operation cancelled.'.
        RETURN.
      ENDIF.

      CLEAR gt_zfir057at1.
      LOOP AT lt_sel_rows INTO DATA(lv_row_idx).
        READ TABLE lt_config INTO DATA(ls_config) INDEX lv_row_idx.
        APPEND ls_config TO gt_zfir057at1.
      ENDLOOP.

      WRITE: / '>> User selected', lines( gt_zfir057at1 ), 'tasks. Starting execution...'.
      PERFORM frm_getdata_push.

    CATCH cx_salv_msg.
  ENDTRY.
ENDFORM.