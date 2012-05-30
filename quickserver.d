/*
D2 Simple Socket Server.

Copyright (C) 2012 Jarl André Hübenthal

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

module quickserver.server;

import std.conv, std.socket, std.stdio, core.thread, std.string, std.ascii;

import quickserver.threadpool;

import quickserver.logger;

class AbstractClientCommandHandler: IClientCommandHandler {
	this(){
		logger = getSimpleLogger();
	}
	
	shared ILogger logger;
	
	final void handleCommand(SocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	void handleCommandImpl(SocketHandler socket, string commandHandler){}
	
	final void gotConnected(SocketHandler socket){
		gotConnectedImpl(socket);
	};
	void gotConnectedImpl(SocketHandler socket){}
	
	final void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	void gotRejectedImpl(Socket socket){}
	
	final void closingConnection(SocketHandler socket){
		closingConnectionImpl(socket);
	};
	void closingConnectionImpl(SocketHandler socket){}
	
	final void lostConnection(SocketHandler socket){
		lostConnectionImpl(socket);
	};
	void lostConnectionImpl(SocketHandler socket){}
}

private interface IClientCommandHandler {
	void gotConnected(SocketHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(SocketHandler handler);
	void lostConnection(SocketHandler handler);
	void handleCommand(SocketHandler handler, string command);
}

private class SocketHandler{
	private Socket socket;
	private shared ILogger logger;
	
	
	public:
	this(Socket sock){
		this.socket = sock;
		this.logger = getSimpleLogger();
	}
	
	void send(string msg){
		int bytesRead = to!int(socket.send(msg~newline));
		if(Socket.ERROR == bytesRead){
			logger.error("An error occured while sending");
		}else{
			logger.info("Sent \""~msg~"\" to client");
		}
	}
}

public class QuickServer {
	auto host 		= "localhost";
	auto port 		= 1234;
	auto name 		= "QuickServer";
	auto blocking 	= false;
	auto backlog 	= 60;
	const auto MAX_CONNECTIONS 	= 120;
	
	IClientCommandHandler commandHandler;
	
	ICThreadPool threadPool;	
	
	shared ILogger logger;
	
	this(string handlerClass){
		commandHandler = cast(IClientCommandHandler) Object.factory(handlerClass);
		enforce(commandHandler);
		logger = getSimpleLogger();
	}
	
	void startServer(){
		Socket listener = new TcpSocket;
		assert(listener.isAlive);
		
		listener.blocking = blocking;
		listener.bind(new InternetAddress(chars(host),to!ushort(port)));
		listener.listen(backlog);
			
		logger.info("Listening on port "~to!string(port));

		threadPool = new CThreadPool(MAX_CONNECTIONS,600,backlog);
		
		SocketSet sset = new SocketSet(MAX_CONNECTIONS+1);
		
		Socket[] reads;
		
		for (;; sset.reset())
		{
			sset.add(listener);

			foreach (Socket each; reads)
			{
				sset.add(each);
			}
			
			Socket.select(sset,null,null);
			
			int i;

			for (i = 0;; i++)
			{
				next:
				if (i == reads.length)
					break;
					
				if (sset.isSet(reads[i]))
				{
					char[1024] buf;
					int read = to!int(reads[i].receive(buf));

					if (Socket.ERROR == read)
					{
						logger.warning("Connection error.");
						goto sock_down;
					}
					else if (0 == read)
					{
						try
						{
							// if the connection closed due to an error, remoteAddress() could fail
							logger.warning("Connection from "~reads[i].remoteAddress().toString()~" closed.");
						}
						catch (SocketException)
						{
							logger.warning("Connection closed.");
						}

						sock_down:
						reads[i].close(); // release socket resources now
						
						// remove from -reads-
						if (i != reads.length - 1)
							reads[i] = reads[reads.length - 1];

						reads = reads[0 .. reads.length - 1];

						logger.info("\tTotal connections: "~to!string(reads.length));

						goto next; // -i- is still the next index
					} 
					else
					{
						auto command = buf[0 .. read];
						auto address = to!string(reads[i].remoteAddress().toString());
						logger.info(to!string("Received "~to!string(read)~"bytes  from "~address~": \""~command~"\""));
						commandHandler.handleCommand(new SocketHandler(reads[i]), to!string(command));
					}
				}
			}
			
			if (sset.isSet(listener)) // connection request
			{
				Socket sn;
				try
				{
					if (reads.length < MAX_CONNECTIONS)
					{
						sn = listener.accept();
						writefln("Connection from %s established.", sn.remoteAddress().toString());
						assert(sn.isAlive);
						assert(listener.isAlive);
						reads ~= sn;
						writefln("\tTotal connections: %d", reads.length);
					}
					else
					{
						sn = listener.accept();
						writefln("Rejected connection from %s; too many connections.", sn.remoteAddress().toString());
						assert(sn.isAlive);
						sn.close();
						assert(!sn.isAlive);
						assert(listener.isAlive);
					}
				}
				catch (Exception e)
				{
					writefln("Error accepting: %s", e.toString());
					if (sn)
						sn.close();
				}
			}
		}
	}
}

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}