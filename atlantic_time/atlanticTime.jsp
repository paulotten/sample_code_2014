<%@ page import="java.util.Calendar" %>
<%
Calendar c = Calendar.getInstance();
c.setTimeZone(TimeZone.getTimeZone("Canada/Atlantic"));
out.println("" + c.get(Calendar.HOUR) + ":"
  + String.format("%02d", c.get(Calendar.MINUTE)) + ":"
  + String.format("%02d", c.get(Calendar.SECOND))); // I should be using <%= %> to output this instead
%>