------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                            Copyright (C) 2004                            --
--                                ACT-Europe                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  $Id$

--  ~ MAIN [SOAP]

with Ada.Text_IO;

with SOAP.Message.Response;
with SOAP.Message.XML;

procedure SOAP5 is

   use Ada;

   Mess : constant String :=
     "<env:Envelope xmlns:env=""http://schemas.xmlsoap.org/soap/envelope/"""
     & " xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"""
     & " xmlns:soapenc=""http://schemas.xmlsoap.org/soap/encoding/"""
     & " xmlns:xsd=""http://www.w3.org/2001/XMLSchema"">"
     & "<env:Header/>"
     & "<env:Body"
     & " env:encodingStyle=""http://schemas.xmlsoap.org/soap/encoding/"">"
     & "<m:isUserInBlackListResponse"
     & " xmlns:m=""http://pfgui:11001/BlackListService"">"
     & "<result xsi:type=""xsd:boolean"">false</result>"
     & "</m:isUserInBlackListResponse></env:Body></env:Envelope>";

   Resp : constant SOAP.Message.Response.Object'Class
     := SOAP.Message.XML.Load_Response (Mess);

begin
   Text_IO.Put_Line (SOAP.Message.XML.Image (Resp));
end SOAP5;
