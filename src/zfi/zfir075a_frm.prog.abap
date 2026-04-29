*&---------------------------------------------------------------------*
*& 包含 ZFIR057A_FRM
*&---------------------------------------------------------------------*

FORM frm_getdata_push.

  " --- 1. 数据定义区 ---
  DATA: lr_data         TYPE REF TO data.
  DATA: lv_submit_prog TYPE program,
        lv_submit_vari TYPE variant.

  " RTTS 描述对象
  DATA: lo_table_descr  TYPE REF TO cl_abap_tabledescr,
        lo_struct_descr TYPE REF TO cl_abap_structdescr,
        lt_components   TYPE cl_abap_structdescr=>component_table,
        ls_component    LIKE LINE OF lt_components.

  FIELD-SYMBOLS: <lt_alv_data> TYPE STANDARD TABLE,
                 <ls_row>      TYPE any,
                 <lv_value>    TYPE any.

  " --- 2. 获取配置表数据 ---
  IF p_back = 'X'.
    SELECT * FROM zfir057at1
       INTO CORRESPONDING FIELDS OF TABLE gt_zfir057at1
       WHERE zblock_push = ''.
  ELSE.

  ENDIF.


  SELECT * FROM zfir057at2
    INTO TABLE @DATA(lt_zfir057at2).

  IF sy-subrc = 0.
    SORT lt_zfir057at2 BY progname variant.
  ENDIF.

  " 预定义映射内表
  DATA: lt_mapping LIKE lt_zfir057at2.

  " --- 3. 循环处理每一个 ALV 程序 ---
  LOOP AT gt_zfir057at1 INTO DATA(ls_zfir057at1).

    " 重置关键指针和变量
    CLEAR: lv_submit_prog, lv_submit_vari, lt_mapping.
    IF <lt_alv_data> IS ASSIGNED.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    lv_submit_prog = to_upper( condense( ls_zfir057at1-progname ) ).
    lv_submit_vari = to_upper( condense( ls_zfir057at1-variant ) ).

    IF lv_submit_prog IS INITIAL. CONTINUE. ENDIF.

    " --- 4. 设置运行时参数并执行 ---
    cl_salv_bs_runtime_info=>clear( ).
    cl_salv_bs_runtime_info=>set(
      EXPORTING
        display  = abap_false
        metadata = abap_false
        data     = abap_true
    ).

    SUBMIT (lv_submit_prog) USING SELECTION-SET lv_submit_vari AND RETURN.

    " --- 5. 获取数据 ---
    TRY.
        cl_salv_bs_runtime_info=>get_data_ref( IMPORTING r_data = lr_data ).
        ASSIGN lr_data->* TO <lt_alv_data>.
      CATCH cx_salv_bs_sc_runtime_info.
        WRITE: / '警告：程序', lv_submit_prog, '未返回 ALV 数据'.
        cl_salv_bs_runtime_info=>clear( ).
        CONTINUE.
    ENDTRY.

    " --- 6. 处理输出逻辑 ---
    IF <lt_alv_data> IS ASSIGNED AND <lt_alv_data> IS NOT INITIAL.

      " 提取当前程序对应的字段映射
      lt_mapping = VALUE #( FOR ls_m IN lt_zfir057at2
                             WHERE ( progname = lv_submit_prog AND variant = lv_submit_vari )
                             ( ls_m ) ).

      WRITE: / '-------------------------------------------'.
      WRITE: / '执行程序:', lv_submit_prog, ' 变式:', lv_submit_vari.


      TRY.
          lo_table_descr ?= cl_abap_tabledescr=>describe_by_data( <lt_alv_data> ).
          lo_struct_descr ?= lo_table_descr->get_table_line_type( ).
          lt_components = lo_struct_descr->get_components( ).
          LOOP AT lt_components INTO DATA(ls_comp).
            " 过滤掉所有'动态地址型'和'嵌套表型'的复杂字段
            IF ls_comp-type->type_kind = 'h' OR   " Internal Table (内表)
               ls_comp-type->type_kind = 's' OR   " 虽然是扁平的，但它还是个结构，
               ls_comp-type->type_kind = 'u' OR   " Deep Structure (深度结构，通常含内表)
               ls_comp-type->type_kind = 'v' OR   " Data Reference (数据引用)
               ls_comp-type->type_kind = 'l'.     " Object Reference (对象引用)

              DELETE TABLE lt_components FROM ls_comp.
              CONTINUE.
            ENDIF.

            " 此时：
            " 'g' (String) 会保留 -> 对应 DB 的 VARCHAR(MAX)
            " 'y' (XString) 会保留 -> 对应 DB 的 VARBINARY
            "                               如果你的目的是建表，'s' 通常也需要展开或删除。
            "  既然你保留了它们，在后续拼接 SQL 语句时，请记得在 MySQL/SQL Server 中为 g 分配 VARCHAR(MAX)，为 y 分配 VARBINARY(MAX)。
          ENDLOOP.


          cl_salv_bs_runtime_info=>clear( ).

          IF ls_zfir057at1-zsfshowfield = 'X'.



            IF sy-mandt = '600' OR sy-mandt = '800'.
            ELSE.
*            1. 定义 alv 显示用的中间结构
              TYPES: BEGIN OF ty_comp_output,
                       name          TYPE abap_compname,    " 字段名
                       type_kind     TYPE abap_typekind,    " 类型
                       length        TYPE i,                " 长度
                       decimals      TYPE i,                " 小数位
                       absolute_name TYPE string,           " 参考字典类型
                     END OF ty_comp_output.
              DATA: lt_comp_output TYPE TABLE OF ty_comp_output.

              " 2. 提取元数据到中间表
              LOOP AT lt_components INTO ls_comp.
                APPEND INITIAL LINE TO lt_comp_output ASSIGNING FIELD-SYMBOL(<ls_out>).
                <ls_out>-name      = ls_comp-name.
                <ls_out>-type_kind = ls_comp-type->type_kind.
                <ls_out>-length    = ls_comp-type->length.
                <ls_out>-decimals  = ls_comp-type->decimals.

                " 清洗绝对路径名称
                <ls_out>-absolute_name = ls_comp-type->absolute_name.
                REPLACE FIRST OCCURRENCE OF '\TYPE=' IN <ls_out>-absolute_name WITH ''.
                REPLACE FIRST OCCURRENCE OF '\DATA=' IN <ls_out>-absolute_name WITH ''.
              ENDLOOP.

              " 3. 调用 SALV 弹出展示
              DATA: lo_alv_comp TYPE REF TO cl_salv_table.
              TRY.
                  cl_salv_table=>factory(
                    IMPORTING
                      r_salv_table = lo_alv_comp
                    CHANGING
                      t_table      = lt_comp_output ).

                  " 设置为弹窗模式
                  lo_alv_comp->set_screen_popup(
                    start_column = 10
                    end_column   = 150
                    start_line   = 5
                    end_line     = 20 ).

                  " 开启基础功能（搜索、排序、过滤）
                  lo_alv_comp->get_functions( )->set_all( abap_true ).

                  " 修改列标题（可选）
                  DATA(lo_cols) = lo_alv_comp->get_columns( ).
                  lo_cols->set_optimize( abap_true ).
                  lo_cols->get_column( 'NAME' )->set_short_text( '字段名' ).
                  lo_cols->get_column( 'TYPE_KIND' )->set_short_text( '类型' ).
                  lo_cols->get_column( 'LENGTH' )->set_short_text( '长度(B)' ).
                  lo_cols->get_column( 'DECIMALS' )->set_short_text( '小数位' ).
                  lo_cols->get_column( 'ABSOLUTE_NAME' )->set_short_text( '参考字典' ).
                  " 显示
                  lo_alv_comp->display( ).

                CATCH cx_salv_msg.
                  MESSAGE '元数据展示弹窗调用失败' TYPE 'E'.
              ENDTRY.
            ENDIF.
          ENDIF.
        CATCH cx_root.
          WRITE: / '错误: 动态结构解析失败'.
      ENDTRY.


      " =====================================================================
      " [新增] 动态往结构定义 (lt_components) 的最前面插入 ID, YEAR, MONTH
      " =====================================================================
      " 1. 准备数据类型的描述对象 (C32 对应 UUID, C4 对应年, C2 对应月)
      DATA: lo_elem_id    TYPE REF TO cl_abap_elemdescr,
            lo_elem_year  TYPE REF TO cl_abap_elemdescr,
            lo_elem_month TYPE REF TO cl_abap_elemdescr.


      lo_elem_id    = cl_abap_elemdescr=>get_c( 32 ).

      IF ls_zfir057at1-zsfyearmonth = 'X'.
        lo_elem_year  = cl_abap_elemdescr=>get_c( 4 ).
        lo_elem_month = cl_abap_elemdescr=>get_c( 2 ).
      ENDIF.


      " 2. 按照顺序插入到 1, 2, 3 的位置
      INSERT VALUE #( name = 'ID'    type = lo_elem_id )    INTO lt_components INDEX 1.
      IF ls_zfir057at1-zsfyearmonth = 'X'..
        INSERT VALUE #( name = 'YEAR'  type = lo_elem_year )  INTO lt_components INDEX 2.
        INSERT VALUE #( name = 'MONTH' type = lo_elem_month ) INTO lt_components INDEX 3.
      ENDIF.

      IF lt_mapping IS NOT INITIAL.

        SORT lt_mapping BY sapfield.
*        目的是为了删除多余的字段
        LOOP AT lt_components INTO ls_component.
          IF ls_component-name = 'ID' OR ls_component-name = 'YEAR' OR ls_component-name = 'MONTH'.
            CONTINUE.
          ENDIF.
          READ TABLE lt_mapping INTO DATA(ls_mapping) WITH KEY sapfield = ls_component-name.
          IF sy-subrc <> 0.
            DELETE TABLE lt_components FROM ls_component.
          ENDIF.
        ENDLOOP.

        WRITE: / '输出模式: 部分字段自动输出'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1  .

      ELSE.
        " 情况 B: 全字段自动输出
        WRITE: / '输出模式: 全字段自动输出'.
        PERFORM frm_crud_targetdata TABLES lt_components <lt_alv_data> USING ls_zfir057at1  .

      ENDIF.

      " --- 循环内清理 ---
      REFRESH lt_mapping.
      UNASSIGN <lt_alv_data>.
    ENDIF.

    " 确保环境被清理，防止干扰
    cl_salv_bs_runtime_info=>clear( ).

  ENDLOOP.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form frm_delete_targetdata
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*&      --> LS_ZFIR057AT1
*&---------------------------------------------------------------------*
FORM frm_crud_targetdata TABLES lt_components   TYPE cl_abap_structdescr=>component_table
                                pt_table TYPE STANDARD TABLE
                          USING ps_zfir057at1   TYPE ts_zfir057at1.

  DATA:lv_target_tbname TYPE tabname.
  DATA:lt_val_tab TYPE TABLE OF rsparams.
  DATA:lv_where TYPE string.

  " 修正类型名称：使用系统中存在的 TT_NAMED_SELTABS
  DATA: lt_shdb_seltables TYPE cl_shdb_seltab=>tt_named_seltables,
        ls_shdb_seltables LIKE LINE OF lt_shdb_seltables. " 对应行类型通常是 ts_named_seltab

  DATA: lt_where_clauses TYPE TABLE OF string.

  IF ps_zfir057at1-tabname IS NOT INITIAL.
    lv_target_tbname = condense( ps_zfir057at1-tabname ).
  ENDIF.

  SELECT * FROM zfir057at3
    INTO TABLE @DATA(lt_zfir057at3)
    WHERE progname = @ps_zfir057at1-progname
      AND variant  = @ps_zfir057at1-variant.
  IF sy-subrc = 0.

    SORT lt_zfir057at3 BY sapfield.
    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report               = ps_zfir057at1-progname
        variant              = ps_zfir057at1-variant
*       MOVE_OR_WRITE        = 'W'
*       NO_IMPORT            = ' '
*       EXECUTE_DIRECT       = ' '
*       GET_P_XML_TAB        =
* IMPORTING
*       SP                   =
*       P_XML_TAB            =
      TABLES
*       L_PARAMS             =
*       L_PARAMS_NONV        =
*       L_SELOP              =
*       L_SELOP_NONV         =
        valutab              = lt_val_tab
*       VALUTABL             =
*       OBJECTS              =
*       VARIVDATS            =
*       FREE_SELECTIONS_DESC =
*       FREE_SELECTIONS_VALUE       =
*       FREE_SELECTIONS_OBJ  =
      EXCEPTIONS
        variant_non_existent = 1
        variant_obsolete     = 2
        OTHERS               = 3.
    IF sy-subrc <> 0.
* Implement suitable error handling here
    ENDIF.

    LOOP AT lt_val_tab INTO DATA(ls_val_tab).
*      如果我没有读到就删除掉这个查询条件
      READ TABLE lt_zfir057at3 INTO DATA(ls_zfir057at3) WITH KEY sapfield = ls_val_tab-selname BINARY SEARCH.
      IF sy-subrc <> 0.
        DELETE TABLE lt_val_tab FROM ls_val_tab.
        CONTINUE.
      ENDIF.


      IF ls_val_tab-low IS INITIAL AND ls_val_tab-high IS INITIAL.
        DELETE TABLE lt_val_tab FROM ls_val_tab.
        CONTINUE.
      ENDIF.

      TYPES: tt_range_string TYPE RANGE OF string.


      IF ls_zfir057at3-reffiled IS NOT INITIAL.
        DATA: lr_ref_data TYPE REF TO data.
        TRY.
            " 1. 根据配置表里的数据元素动态开辟变量
            CREATE DATA lr_ref_data TYPE (ls_zfir057at3-reffiled).
            FIELD-SYMBOLS: <lv_ref_val> TYPE any.
            ASSIGN lr_ref_data->* TO <lv_ref_val>.

            " 2. 动态抓取字典真实长度
            DESCRIBE FIELD <lv_ref_val> LENGTH DATA(lv_len) IN CHARACTER MODE.

            " 3. 处理 LOW 值
            IF ls_val_tab-low IS NOT INITIAL.
              DATA(lv_low_clean) = condense( ls_val_tab-low ). " 清理多余空格

              IF ls_zfir057at3-sapconv = 'I'.
                " 【SAP 标准 I (Input)】: 外部数据进入系统 -> 补全前导 0
                ls_val_tab-low = |{ lv_low_clean WIDTH = lv_len ALIGN = RIGHT PAD = '0' }|.
              ELSEIF ls_zfir057at3-sapconv = 'O'.
                " 【SAP 标准 O (Output)】: 系统数据向外展示 -> 去除前导 0
                SHIFT lv_low_clean LEFT DELETING LEADING '0'.
                ls_val_tab-low = lv_low_clean.
              ENDIF.
            ENDIF.

            " 4. 处理 HIGH 值
            IF ls_val_tab-high IS NOT INITIAL.
              DATA(lv_high_clean) = condense( ls_val_tab-high ).

              IF ls_zfir057at3-sapconv = 'I'.
                " 【SAP 标准 I (Input)】: 补全前导 0
                ls_val_tab-high = |{ lv_high_clean WIDTH = lv_len ALIGN = RIGHT PAD = '0' }|.
              ELSEIF ls_zfir057at3-sapconv = 'O'.
                " 【SAP 标准 O (Output)】: 去除前导 0
                SHIFT lv_high_clean LEFT DELETING LEADING '0'.
                ls_val_tab-high = lv_high_clean.
              ENDIF.
            ENDIF.

            " 5. 释放内存
            IF <lv_ref_val> IS ASSIGNED.
              UNASSIGN <lv_ref_val>.
            ENDIF.
            CLEAR lr_ref_data.

          CATCH cx_sy_create_data_error.
            WRITE: / '警告: 未找到字典类型', ls_zfir057at3-reffiled.
        ENDTRY.

      ENDIF.

      IF ls_val_tab-kind = 'P'.
        IF ls_val_tab-low IS NOT INITIAL.
          APPEND |{ ls_zfir057at3-dbfield } = '{ ls_val_tab-low }'| TO lt_where_clauses.
        ENDIF.
      ELSEIF ls_val_tab-kind = 'S'.

        IF ls_val_tab-low IS NOT INITIAL OR ls_val_tab-high IS NOT INITIAL.
          CLEAR ls_shdb_seltables.
          ls_shdb_seltables-name = ls_zfir057at3-dbfield.

          DATA: lr_range_table TYPE REF TO data.
          " [修改点1] 使用我们自己定义的标准 Range 类型
          CREATE DATA lr_range_table TYPE tt_range_string.

          " [修改点2] 指针类型也换成我们的标准类型
          FIELD-SYMBOLS: <lt_range> TYPE tt_range_string.
          ASSIGN lr_range_table->* TO <lt_range>.

          " [修改点3] 此时可以直接光明正大地使用 option 字段了
          APPEND VALUE #( sign   = ls_val_tab-sign
                          option = ls_val_tab-option
                          low    = ls_val_tab-low
                          high   = ls_val_tab-high ) TO <lt_range>.

          IF <lt_range> IS NOT INITIAL.
            " [优化点] lr_range_table 本身就是 REF TO data，直接赋给 dref，不需要再用 REF #() 重新抓取引用了，这样最安全
            ls_shdb_seltables-dref = lr_range_table.
            APPEND ls_shdb_seltables TO lt_shdb_seltables.
            CLEAR: ls_shdb_seltables.
          ENDIF.

          IF <lt_range> IS ASSIGNED.
            UNASSIGN <lt_range>.
          ENDIF.

          IF lt_shdb_seltables IS NOT INITIAL.
            TRY.
                " 调用转换方法
                DATA(lv_s_where) = cl_shdb_seltab=>combine_seltabs(
                  it_named_seltabs = lt_shdb_seltables
                ).

                " 如果转换出的 SQL 片段不为空，则加入汇总表
                IF lv_s_where IS NOT INITIAL.
                  APPEND lv_s_where TO lt_where_clauses.
                ENDIF.

              CATCH cx_shdb_exception.
                " 这里可以添加异常处理，例如 WRITE: / 'SQL 转换异常'.
            ENDTRY.
          ENDIF.

          CLEAR:lt_shdb_seltables,
                lv_s_where.
        ENDIF.
      ENDIF.
    ENDLOOP.


    IF ps_zfir057at1-zsfyearmonth = 'X'.
      APPEND | YEAR = '{ sy-datum+0(4) }'| TO lt_where_clauses.
      APPEND | MONTH = '{ sy-datum+4(2) }'| TO lt_where_clauses.
    ENDIF.

*    这个时候我得到了 lt_where_clauses
    IF lt_where_clauses IS NOT INITIAL.
      " 将内表中的所有行用 ' AND ' 连接起来
      lv_where = concat_lines_of( table = lt_where_clauses sep = ' AND ' ).
    ENDIF.

*    DATA:lr_result TYPE REF TO data.

    DATA: lo_new_struct_descr TYPE REF TO cl_abap_structdescr,
          lo_new_table_descr  TYPE REF TO cl_abap_tabledescr,
          lr_db_data          TYPE REF TO data. " 这就是你 ADBC 要用的引用

    FIELD-SYMBOLS: <lt_db> TYPE STANDARD TABLE. " 用于后续读取数据的实体内表指针




    TRY.
        " 第一步：用组件表创建动态结构描述对象
        lo_new_struct_descr = cl_abap_structdescr=>create( p_components = lt_components[] ).

        " 第二步：用动态结构创建动态内表描述对象
        lo_new_table_descr = cl_abap_tabledescr=>create( p_line_type = lo_new_struct_descr ).

        " 第三步：在内存中真正开辟这块动态内表的空间 (Data Reference)
        CREATE DATA lr_db_data TYPE HANDLE lo_new_table_descr.

        " 第四步：将指针挂载上去，方便后续直接访问里面的数据
        ASSIGN lr_db_data->* TO <lt_db>.

      CATCH cx_root INTO DATA(lx_rtts_err).
        WRITE: / '动态表生成失败:', lx_rtts_err->get_text( ).
        RETURN.
    ENDTRY.


    " =======================================================================
    " 2. 结合 ADBC (cl_sql_connection) 执行带 WHERE 的动态查询
    " =======================================================================
    DATA: go_db         TYPE REF TO cl_sql_connection,
          go_sqlerr_ref TYPE REF TO cx_sql_exception.

    TRY.
        " 连接外部数据库 (确保 'ps_zfir057at1-dbname' 是你 DBCO 里配好的连接)
        go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).

        " 拼装原生 SELECT * SQL 语句
        DATA(lv_stmt) = |SELECT * FROM { lv_target_tbname }|.
        IF lv_where IS NOT INITIAL.
          lv_stmt = |{ lv_stmt } WHERE { lv_where }|.
        ENDIF.

        " 创建 Statement 并执行
        DATA(lo_stmt_ref) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).
        DATA(lo_res_ref)  = lo_stmt_ref->execute_query( lv_stmt ).

        " 核心：把刚刚动态生成的 lr_db_data 直接喂给 ADBC 的输出表
        " (因为 lr_db_data 本身就是 REF TO data，不需要再去 GET REFERENCE OF 了)
        lo_res_ref->set_param_table( lr_db_data ).

        " 抓取数据到内存中，此时 <lt_db> 里面就有数据了！
        DATA(lv_row_cnt) = lo_res_ref->next_package( ).

        " 关闭游标释放资源
        lo_res_ref->close( ).

        WRITE: / '成功从外部数据库查出', lv_row_cnt, '条数据'.

      CATCH cx_sql_exception INTO go_sqlerr_ref.
        MESSAGE go_sqlerr_ref->sql_message TYPE 'E'.
    ENDTRY.


    IF <lt_db> IS NOT INITIAL.

      " --- 极度重要的安全检查：绝不能在 WHERE 为空时执行删除 ---
      IF lv_target_tbname IS NOT INITIAL AND lv_where IS NOT INITIAL.


        TRY.
            " 1. 获取外部数据库连接
            go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).

            " 2. 直接拼接完整的 DELETE SQL 语句
            " 注意：这里直接把完整的 WHERE 条件放进去了
            DATA(l_stmt_bulk_del) = |DELETE FROM { lv_target_tbname } WHERE { lv_where }|.

            " 3. 创建 Statement 对象
            DATA(l_stmt_ref_del) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).

            " 4. 一次性执行批量删除
            DATA(l_rows_deleted) = l_stmt_ref_del->execute_update( l_stmt_bulk_del ).

            " 5. 提交事务 (外部系统写入/删除必须 COMMIT)
            go_db->commit( ).


            " 输出成功日志
            WRITE: / '批量删除成功，受影响的行数:', l_rows_deleted.

          CATCH cx_sql_exception INTO go_sqlerr_ref.
            " 核心修复：捕获 rollback 自身的异常
            IF go_db IS NOT INITIAL.
              TRY.
                  go_db->rollback( ).
                CATCH cx_sql_exception.
                  " 忽略回滚时发生的异常
              ENDTRY.
            ENDIF.
            MESSAGE go_sqlerr_ref->sql_message TYPE 'E'.

          CATCH cx_parameter_invalid INTO DATA(lx_param).
            MESSAGE lx_param->get_text( ) TYPE 'E'.

        ENDTRY.

      ELSE.
        WRITE: / '警告：表名或 WHERE 条件为空，已终止批量删除操作以保护数据！'.
      ENDIF.
    ENDIF.


    " *****准备把数据写入对方数据库

    IF pt_table[] IS NOT INITIAL.

      " 1. 清空之前 SELECT 查出来的老数据，准备装载新数据
      CLEAR <lt_db>.

      " 2. 动态创建单行结构指针，用于数据映射
      DATA: lr_db_row TYPE REF TO data.
      CREATE DATA lr_db_row TYPE HANDLE lo_new_struct_descr.
      FIELD-SYMBOLS: <ls_db_row> TYPE any.
      ASSIGN lr_db_row->* TO <ls_db_row>.

      " 3. 循环源数据，精准提取 lt_components 里存在的字段
      LOOP AT pt_table ASSIGNING FIELD-SYMBOL(<ls_pt_row>).
        CLEAR <ls_db_row>.

        LOOP AT lt_components INTO DATA(ls_comp_map).
          " 从 ALV 源数据行取值
          ASSIGN COMPONENT ls_comp_map-name OF STRUCTURE <ls_pt_row> TO FIELD-SYMBOL(<lv_src_val>).
          IF sy-subrc = 0.
            " 赋值给外部数据库的动态行
            ASSIGN COMPONENT ls_comp_map-name OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_val>).
            IF sy-subrc = 0.
              <lv_tgt_val> = <lv_src_val>.
            ENDIF.
          ENDIF.
        ENDLOOP.

        " --- 强行注入动态数据 (ID, YEAR, MONTH) ---
        " A. 生成 32 位 UUID (使用 TRY CATCH 防止类报错导致 Dump)
        TRY.
            DATA(lv_new_uuid) = cl_uuid_factory=>create_system_uuid( )->create_uuid_c32( ).
          CATCH cx_uuid_error.
            lv_new_uuid = sy-sysid && sy-datum && sy-uzeit. " 降级容错方案
        ENDTRY.

        " B. 给动态结构的新增字段赋值
        ASSIGN COMPONENT 'ID' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_id>).
        IF sy-subrc = 0. <lv_tgt_id> = lv_new_uuid. ENDIF.


        IF ps_zfir057at1-zsfyearmonth = 'X'.
          ASSIGN COMPONENT 'YEAR' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_year>).
          IF sy-subrc = 0. <lv_tgt_year> = sy-datum+0(4). ENDIF.

          ASSIGN COMPONENT 'MONTH' OF STRUCTURE <ls_db_row> TO FIELD-SYMBOL(<lv_tgt_month>).
          IF sy-subrc = 0. <lv_tgt_month> = sy-datum+4(2). ENDIF.
        ENDIF.

        " 将映射好的单行加入动态内表
        APPEND <ls_db_row> TO <lt_db>.
      ENDLOOP.



      " 4. 组装动态 INSERT SQL 语句
      IF <lt_db> IS NOT INITIAL.
        DATA: lt_fields TYPE TABLE OF string,
              lt_values TYPE TABLE OF string.

        " 根据组件表动态生成： (FIELD1, FIELD2) VALUES (?, ?)
        LOOP AT lt_components INTO DATA(ls_comp_sql).
          APPEND ls_comp_sql-name TO lt_fields.
          APPEND '?' TO lt_values.
        ENDLOOP.

        DATA(lv_fields_str) = concat_lines_of( table = lt_fields sep = ',' ).
        DATA(lv_vals_str)   = concat_lines_of( table = lt_values sep = ',' ).

        DATA(lv_insert_sql) = |INSERT INTO { lv_target_tbname } ( { lv_fields_str } ) VALUES ( { lv_vals_str } )|.

        " 5. 执行 ADBC 批量插入
        TRY.
            " 确保连接存在
            IF go_db IS INITIAL.
              go_db = cl_sql_connection=>get_connection( ps_zfir057at1-dbname ).
            ENDIF.

            DATA(lo_stmt_insert) = go_db->create_statement( tab_name_for_trace = lv_target_tbname ).

            " 核心：直接绑定整张内表
            lo_stmt_insert->set_param_table( lr_db_data ).

            " 执行批量写入
            DATA(lv_inserted_cnt) = lo_stmt_insert->execute_update( lv_insert_sql ).
            go_db->commit( ).

*            lo_stmt_insert->close( ).
            WRITE: / '成功写入目标数据库，条数:', lv_inserted_cnt.

          CATCH cx_sql_exception INTO DATA(lx_sql_ins).
            IF go_db IS NOT INITIAL.
              TRY.
                  go_db->rollback( ).
                CATCH cx_sql_exception.
              ENDTRY.
            ENDIF.
            MESSAGE lx_sql_ins->sql_message TYPE 'E'.

          CATCH cx_parameter_invalid INTO DATA(lx_param_ins).
            MESSAGE lx_param_ins->get_text( ) TYPE 'E'.
        ENDTRY.

      ENDIF.

    ENDIF.

  ENDIF.

ENDFORM.
*&---------------------------------------------------------------------*
*& Form frm_fore_select_config
*&---------------------------------------------------------------------*
*& text
*&---------------------------------------------------------------------*
*& -->  p1        text
*& <--  p2        text
*&---------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*& Form frm_fore_select_config
*& 描述: 前台模式下，先弹出 zfir057at1 配置表供用户人工勾选要执行的程序
*&---------------------------------------------------------------------*
FORM frm_fore_select_config.

  DATA: lt_config TYPE TABLE OF zfir057at1,
        lo_alv    TYPE REF TO cl_salv_table.

  " 1. 获取所有未冻结的配置
  SELECT * FROM zfir057at1
    INTO TABLE @lt_config
    WHERE zblock_push = ''.

  IF sy-subrc <> 0.
    MESSAGE '未找到可执行的配置记录！' TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  " 2. 弹窗显示配置表
  TRY.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_config ).

      " 开启多选和全部工具栏
      lo_alv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>multiple ).
      lo_alv->get_functions( )->set_all( abap_true ).

      " 设置为弹窗模式 (大小可以根据实际列数调整)
      lo_alv->set_screen_popup( start_column = 10 end_column = 120 start_line = 5 end_line = 20 ).

      WRITE: / '>> 正在等待用户在主控台中选择要执行的配置...'.
      lo_alv->display( ).

      " 3. 获取用户勾选的行
      DATA(lt_sel_rows) = lo_alv->get_selections( )->get_selected_rows( ).

      IF lt_sel_rows IS INITIAL.
        WRITE: / '>> 用户未选择任何配置，操作已取消。'.
        RETURN.
      ENDIF.

      " 4. 将选中的数据写入全局表 gt_zfir057at1 (黄金版本的核心驱动表)
      CLEAR gt_zfir057at1.
      LOOP AT lt_sel_rows INTO DATA(lv_row_idx).
        READ TABLE lt_config INTO DATA(ls_config) INDEX lv_row_idx.
        IF sy-subrc = 0.
          APPEND ls_config TO gt_zfir057at1.
        ENDIF.
      ENDLOOP.

      WRITE: / '>> 用户选中了', lines( gt_zfir057at1 ), '个配置，开始往下执行...'.

      " 5. 无缝衔接原有黄金版本的主逻辑
      PERFORM frm_getdata_push.

    CATCH cx_salv_msg.
      WRITE: / '配置表弹窗生成失败'.
  ENDTRY.

ENDFORM.
