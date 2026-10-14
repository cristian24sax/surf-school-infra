
moved {
  from = aws_lb.surf_school
  to   = aws_lb.surf_school[0]
}

moved {
  from = aws_lb_listener.http
  to   = aws_lb_listener.http[0]
}
