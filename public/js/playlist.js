$(document).ready(function() {
  $("td.path").each(function() {
    var old_path=$(this).text();
    console.log(old_path)
    var new_path=old_path.replace("/Users/farrisl", "/mm");
    console.log(new_path);
    $(this).text(new_path);
    console.log($(this).text());
    $(this).after("<td class='audio'><audio src=\""+new_path+"\" controls='controls'></td>");
  });
});
