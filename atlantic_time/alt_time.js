function startTimer()
{
  setInterval(updateTime,500);
}

function updateTime()
{
  // legecy internet explorer support not included

  ajax = new XMLHttpRequest();
  ajax.onreadystatechange=function()
  {
    if (ajax.readyState == 4 && ajax.status == 200)
	{
	  document.getElementById("timeField").innerHTML = ajax.responseText;
	}
  }
  ajax.open("GET", "atlanticTime.jsp", true);
  ajax.send();
}
