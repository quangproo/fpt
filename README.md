<body>
<style>
.box_1 { display:flex; position:absolute; width:200px; height:60px; border:solid; align-items:center; justify-content:center; }
.line_v { position:absolute; width:2px; background:black; }
.line_h { position:absolute; height:2px; background:black; }
.line_iser { position:absolute; height:3px; background:blue; }
.line_snmp { position:absolute; border-left:2px dashed darkorange; }
</style>
<h2 style="text-align:center">Sơ đồ Kiến trúc mạng</h2>

<!-- Bàn cờ vua: top bottom = A1 -->
<div style="position:relative; width:900px; height:580px; margin:20px auto;">
  <!-- ========== BOXES ========== -->

  <!-- A4: ESXi + Monitor -->
  <div style="position:absolute; left:30px; top:30px; width:240px; height:120px; border:solid;">
    <div style="padding:4px 8px; border-bottom:1px solid; text-align:center;">ESXi</div>
    <div style="margin:6px 10px; height:72px; width:100px; border:solid; display:flex; align-items:center; justify-content:center;">Monitor</div>
  </div>

  <!-- B4: Switch iSER -->
  <div class="box_1" style="left:350px; top:30px;">Switch iSER</div>

  <!-- C4: SAN -->
  <div class="box_1" style="left:650px; top:30px;">SAN</div>

  <!-- B3: Switch CAT6 -->
  <div class="box_1" style="left:350px; top:200px;">Switch CAT6</div>

  <!-- B2: Router -->
  <div class="box_1" style="left:350px; top:340px;">Router</div>

  <!-- B1: Internet -->
  <div class="box_1" style="left:350px; top:480px;">Internet</div>


  <!-- ========== ĐƯỜNG KẾT NỐI ========== -->

  <!-- ESXi(A4) ↔ Switch iSER(B4) -->
  <div class="line_iser" style="left:270px; top:59px; width:80px;"></div>
  <span style="position:absolute; left:285px; top:43px; font-size:11px; color:blue; font-weight:bold;">iSER</span>

  <!-- Switch iSER(B4) ↔ SAN(C4) -->
  <div class="line_iser" style="left:550px; top:59px; width:100px;"></div>
  <span style="position:absolute; left:578px; top:43px; font-size:11px; color:blue; font-weight:bold;">iSER</span>

  <!-- Switch iSER(B4) ↔ Switch CAT6(B3) -->
  <div class="line_v" style="left:449px; top:90px; height:110px;"></div>

  <!-- ESXi(A4) ↔ A3 -->
  <div class="line_v" style="left:149px; top:150px; height:80px;"></div>

  <!-- A3 ↔ Switch CAT6(B3) -->
  <div class="line_h" style="left:150px; top:229px; width:200px;"></div>

  <!-- SAN(C4) ↔ C3 -->
  <div class="line_v" style="left:749px; top:90px; height:140px;"></div>

  <!-- C3 ↔ Switch CAT6(B3) -->
  <div class="line_h" style="left:550px; top:229px; width:200px;"></div>

  <!-- Switch CAT6(B3) -->
  <div class="line_v" style="left:449px; top:260px; height:80px;"></div>

  <!-- Router(B2) ↔ Internet(B1) -->
  <div class="line_v" style="left:449px; top:400px; height:80px;"></div>

  <!-- Switch iSER(B4) ↔ lên Switch CAT6(B3) (SNMP) -->
  <div style="position:absolute; left:458px; top:200px; width:0; height:0;border-left:5px solid transparent; border-right:5px solid transparent;border-top:8px solid darkorange;"></div>
  <div class="line_snmp" style="left:462px; top:90px; width:0; height:110px;"></div>
  <span style="position:absolute; left:466px; top:135px; font-size:11px; color:darkorange; font-weight:bold;">SNMP</span>

</div>
