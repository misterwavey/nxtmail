import socket              
import threading
import pymysql
from pymysql.err import IntegrityError
import string
import time

CMD_REGISTER                   = 1
CMD_CHECK_REGISTERED_NICKNAME  = 2
CMD_SEND_MESSAGE               = 3
CMD_MESSGAGE_COUNT             = 4
CMD_GET_MESSAGE                = 5
CMD_JOIN_POOL                  = 6 
CMD_GET_POOL                   = 7 

STATUS_OK                      = 0
STATUS_INVALID_PROTOCOL        = 1
STATUS_INVALID_CMD             = 2
STATUS_INVALID_APP             = 3
STATUS_INVALID_USERID          = 4
STATUS_INVALID_LENGTH          = 5
STATUS_INTERNAL_ERROR          = 6
STATUS_MISSING_NICKNAME        = 7
STATUS_MISSING_MESSAGE         = 8
STATUS_UNIMPLEMENTED           = 9
STATUS_MISSING_MESSAGE_ID      = 10
STATUS_MISSING_POOL_SIZE       = 11
STATUS_MISSING_POOL_ID         = 12

STATUS_USER_ALREADY_REGISTERED = 101
STATUS_UNREGISTERED_NICKNAME   = 102
STATUS_UNKNOWN_USERID          = 103
STATUS_UNREGISTERED_USERID     = 104
STATUS_UNKNOWN_POOL_ID         = 105

STATUS_REGISTER_OK             = 201
STATUS_COUNT_OK                = 202
STATUS_GET_MESSAGE_OK          = 203
STATUS_INVALID_MESSAGE_ID      = 204
STATUS_JOINED_POOL             = 205
STATUS_INVALID_POOLSIZE        = 206
STATUS_ALREADY_JOINED_POOL     = 207
STATUS_POOL_UNFILLED           = 208
STATUS_POOL_FILLED             = 209



def on_new_client(clientsocket, addr, db):
    done = False
    while not done:
      request = clientsocket.recv(1024)
      response = handle_request(request, addr, db)
      try:
        clientsocket.send(response)
      except BrokenPipeError:
        clientsocket.close()
        done = True

def handle_request(request, addr, db):
  threadName = threading.currentThread().name
  db.ping(reconnect=True)
  if len(request) < 24:
    response = build_response(STATUS_INVALID_LENGTH)
    rLen = len(request)
    print("<{threadName}-{addr}>: short request: {request} len {rLen}. Response {response}".format(**locals()))
    return response
  else:
    protoMajor = request[0]
    protoMinor = request[1]
    cmd        = request[2]
    appId      = request[3]
    userId     = request[4:9].decode() + "-" + request[9:14].decode() + "-" + \
                 request[14:19].decode() + "-" + request[19:24].decode()
    nickname   = "" #optional
    message    = "" #optional

    print("<{threadName}-{addr}>: request: {request} maj {protoMajor} min {protoMinor} cmd {cmd} appid {appId} userId ".format(**locals()))
    if not(protoMajor == 0 and protoMinor == 1):
      response = build_response(STATUS_INVALID_PROTOCOL)
      print("<{threadName}-{addr}>: invalid protocol: {request}. Response {response}".format(**locals()))
      return response

    if not(isValidUserId(userId, db)):
      response = build_response(STATUS_UNKNOWN_USERID)
      print ("<{threadName}-{addr}>: userId {userId} is not registered with mbox in db. Response {response}".format(**locals()))
      return response
 
    if cmd == CMD_REGISTER:
      return handle_register(appId, userId, addr, db)

    elif cmd == CMD_CHECK_REGISTERED_NICKNAME:
      nickname = parse_param_as_nickname(request)
      return handle_check_registered_nickname(appId, userId, nickname, addr, db)

    elif cmd == CMD_SEND_MESSAGE:    
      nickname = parse_param_as_nickname(request)
      if nickname == None or len(nickname) == 0:
        response = build_response(STATUS_MISSING_NICKNAME)
        print("<{threadName}-{addr}>: missing nickname: {request}. Response {response}".format(**locals()))
        return response    
      if len(request) > 44:
        message = request[44:301]
        if message == None or len(message) == 0:
          response = build_response(STATUS_MISSING_MESSAGE)
          print("<{threadName}-{addr}>: MISSING message for send msg cmd. Response {response}".format(**locals()))
          return response
        message = message.decode()
        message = message[0:-2] # remove /r/n common to all requests
        printable = set(string.printable) #ascii only
        message = "".join(filter(lambda x: x in printable, message))
        if message == None or len(message) == 0:
          response = build_response(STATUS_MISSING_MESSAGE)
          print("<{threadName}-{addr}>: MISSING message for send msg cmd. Response {response}".format(**locals()))
          return response
        return handle_send(appId, userId, nickname, message, addr, db)
      else:
        response = build_response(STATUS_MISSING_MESSAGE)
        print("<{threadName}-{addr}>: MISSING message for send msg cmd. Response {response}".format(**locals()))
        return response

    elif cmd == CMD_MESSGAGE_COUNT:
      return handle_get_message_count(appId, userId, addr, db)

    elif cmd == CMD_GET_MESSAGE:
      if len(request) < 26: #2bytes for msgid
        print ("<{threadName}-{addr}> missing message Id for get message".format(**locals()))
        return build_response(STATUS_MISSING_MESSAGE_ID)
      else:    
        b = bytes(request[24:26])
        messageId = int.from_bytes(b,byteorder="little")
        print ("<{threadName}-{addr}> extracted '{messageId}' for message id".format(**locals()))
        if messageId < 1:
          print ("<{threadName}-{addr}> invalid number '{messageId}' for message id".format(**locals()))
          return build_response(STATUS_INVALID_MESSAGE_ID)

        return handle_get_message(appId, userId, messageId, addr, db)

    elif cmd == CMD_JOIN_POOL:
      if len(request) < 25:
        print ("<{threadName}-{addr}> missing size for join pool".format(**locals()))
        return build_response(STATUS_MISSING_POOL_SIZE)
      size = request[24]
      return handle_join_pool(appId, userId, size, addr, db)

    elif cmd == CMD_GET_POOL:
      if len(request) < 26: # 2 bytes for poolId
        print ("<{threadName}-{addr}> missing poolId for get pool".format(**locals()))
        return build_response(STATUS_MISSING_POOL_ID)
      else:    
        b = bytes(request[24:26])
        poolId = int.from_bytes(b,byteorder="little")
        print ("<{threadName}-{addr}> extracted '{poolId}' for poolId".format(**locals()))
        if poolId < 1:
          print ("<{threadName}-{addr}> invalid number '{poolId}' for poolId".format(**locals()))
          return build_response(STATUS_INVALID_POOL_ID)

      return handle_get_pool(appId, userId, poolId, addr, db)

    else:
      response = build_response(STATUS_INVALID_CMD)
      print("<{threadName}-{addr}>: invalid cmd: {request}. Response {response}".format(**locals()))
      return response

def handle_get_pool(appId, userId, poolId, addr, db):
  threadName = threading.currentThread().name  
  if not(isValidUserIdForApp(userId, appId, db)):
    response = build_response(STATUS_UNREGISTERED_USERID)
    print ("<{threadName}-{addr}>: userId {userId} is not registered with app {appId} in db. Response {response}".format(**locals()))
    return response 

  cursor = db.cursor()

  # A is our user in an unfilled pool? return it if so
  try:
    sql = """
    select p.poolId from pool p inner join user_in_pool u 
    where 
      p.appId = %s and 
      u.poolId = p.poolId and 
      p.poolId = %s and 
      p.filled=false and 
      u.userId = %s"""     
    cursor.execute(sql, (appId, poolId, userId))
    results = cursor.fetchone()  
    if not(results == None):
      poolId = results[0]
      print("A: user is in an unfilled pool: poolId {poolId}".format(**locals()))
      return bytes([STATUS_POOL_UNFILLED]) 
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return build_response(STATUS_INTERNAL_ERROR)

  # B is our user in a filled pool? return it if so
  try:
    sql = """
    select u.nickname from user u where u.userid in (select u.userId from pool p right join user_in_pool u on u.poolId = p.poolId 
      where 
      p.appid=%s and 
      u.poolId = p.poolId and 
      p.filled=true and 
      p.poolId = %s)"""    
    cursor.execute(sql, (appId, poolId))
    resultNicks = cursor.fetchall()  # TODO these are userIds not nicks - convert
    if not(resultNicks == None) and not(len(resultNicks) == 0):
      response = bytearray(1)
      response[0] = STATUS_POOL_FILLED
      response.extend(len(resultNicks).to_bytes(1, byteorder="little"))
      for i in resultNicks:
        nick = i[0] # take string from tuple
        response.extend(len(nick).to_bytes(1, byteorder="little")) # 1 byte len of nick
        response.extend(nick.encode()) # nick to bytes
      response = bytes(response)
      print ("B: user is in filled pool {poolId} with nicks {resultNicks}. response {response}".format(**locals()))
      return response
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return build_response(STATUS_INTERNAL_ERROR)

  # C our user is not in a pool
  print("C: user is not in named pool: poolId {poolId}".format(**locals()))
  return build_response(STATUS_UNKNOWN_POOL_ID)
  
   
def handle_join_pool(appId, userId, size, addr, db):
  threadName = threading.currentThread().name  
  if not(isValidUserIdForApp(userId, appId, db)):
    response = build_response(STATUS_UNREGISTERED_USERID)
    print ("<{threadName}-{addr}>: userId {userId} is not registered with app {appId} in db. Response {response}".format(**locals()))
    return response 

  if not(size > 1 and size <= 16):
    response = build_response(STATUS_INVALID_POOLSIZE)
    print ("<{threadName}-{addr}>: app {appId} asking for invalid size {size}. Response {response}".format(**locals()))
    return response   

  print ("<{threadName}-{addr}> userId {userId} joining pool of size {size} for appid {appId} in db ".format(**locals()))

  db.begin() # start transaction 
  
  cursor = db.cursor()

  # A is our user already in an unfilled pool? return it if so
  try:
    sql = """
    select p.poolId from pool p inner join user_in_pool u 
    where p.appId = %s and 
      p.size = %s and 
      p.filled = false and 
      u.userId = %s and 
      u.poolId = p.poolId"""     
    cursor.execute(sql, (appId, size, userId))
    results = cursor.fetchone()  
    if not(results == None):
      poolId = results[0]
      return bytes([STATUS_ALREADY_JOINED_POOL] + list(poolId.to_bytes(2, byteorder="little")))
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return build_response(STATUS_INTERNAL_ERROR)

  # B is there an unfilled pool that our user isn't a member of? join if so, otherwise create new pool
  try:
    sql = """
    select p.poolId from pool p inner join user_in_pool u 
    where p.appId = %s and 
      p.size = %s and 
      p.filled = false and 
      u.userId <> %s and 
      u.poolId = p.poolId 
    for update"""      
    cursor.execute(sql, (appId, size, userId))
    results = cursor.fetchone()  
    if results == None:
      return handle_new_pool(appId, userId, size, addr, db)  
    else:
      poolId = results[0]
      return handle_join_unfilled_pool(poolId, appId, userId, size, addr, db)        
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return build_response(STATUS_INTERNAL_ERROR)

def handle_new_pool(appId, userId, size, addr, db):
  threadName = threading.currentThread().name    
  print ("<{threadName}-{addr}> no existing pool of size {size} for appid {appId} in db ".format(**locals()))

  cursor = db.cursor()
  unixtime_ms = time.time_ns() // 1000000

  sql = "INSERT INTO pool (appid, size, filled, created_unixtime_ms, updated_unixtime_ms) VALUES (%s, %s, %s, %s, %s)"
  cursor.execute(sql, (appId, size, False, unixtime_ms, unixtime_ms))

  sql = "select last_insert_id()" # the last row's primary key that was inserted by us
  cursor.execute(sql)
  poolId = cursor.fetchone()[0]

  sql = "INSERT INTO user_in_pool (poolId, userId) VALUES (%s, %s)"
  cursor.execute(sql, (poolId, userId))
  
  db.commit() # transaction end
  response = bytes([STATUS_JOINED_POOL] + list(poolId.to_bytes(2, byteorder="little")))
  return response

def handle_join_unfilled_pool(poolId, appId, userId, size, addr, db):
  cursor = db.cursor()
  sql = "INSERT INTO user_in_pool (poolId, userId) VALUES (%s, %s)"
  cursor.execute(sql, (poolId, userId))

  sql = "select count(*) from user_in_pool where poolId = %s"
  cursor.execute(sql, (poolId))
  results = cursor.fetchone()
  users = results[0]
  if users == size:
    unixtime_ms = time.time_ns() // 1000000
    sql = "update pool set filled=true,updated_unixtime_ms=%s where poolId = %s"
    cursor.execute(sql, (unixtime_ms, poolId))
  
  db.commit() # transaction end
  response = bytes([STATUS_JOINED_POOL] + list(poolId.to_bytes(2, byteorder="little")))
  return response
  

def parse_param_as_nickname(request):
  if len(request) > 24:
    nickname = request[24:43].decode()
    printable = set(string.printable) #ascii only
    nickname = "".join(filter(lambda x: x in printable, nickname))
    return nickname

def handle_send(appId, userId, nickname, message, addr, db):
    threadName = threading.currentThread().name    
    if not(isValidUserIdForApp(userId, appId, db)):
      response = build_response(STATUS_UNREGISTERED_USERID)
      print ("<{threadName}-{addr}>: userId {userId} is not registered with app {appId} in db. Response {response}".format(**locals()))
      return response

    if nickname == "*":
      response = do_send_to_all(appId, userId, message, db)
    else:
      response = do_send_to_nick(appId, userId, nickname, message, addr, db)
    return response


def do_send_to_all(appId, userId, message, db):
    return build_response(STATUS_UNIMPLEMENTED)


def do_send_to_nick(appId, userId, nickname, message, addr, db):
  threadName = threading.currentThread().name    
  print ("<{threadName}-{addr}> checking if nick {nickname} is registered for app {appId} in db ".format(**locals()))
  status = do_check_registered_nickname_for_app(appId, userId, nickname, addr, db)
  if status == STATUS_UNREGISTERED_NICKNAME or status == STATUS_INTERNAL_ERROR:
    return build_response(status)
  else:
    status = do_store_message(userId, appId, nickname, message, addr, db)
    return build_response(status)


def do_store_message(userId, appId, nickname, message, addr, db):
  threadName = threading.currentThread().name    
  print ("<{threadName}-{addr}> userId {userId} storing msg {message} for nickname {nickname} in app {appId} in db ".format(**locals()))
  cursor = db.cursor()
  targetUserId = get_userid_for_nickname(appId, nickname, addr, db)
  if targetUserId == None:
    return STATUS_INTERNAL_ERROR

  unixtime_ms = time.time_ns() // 1000000 #meh
  try:
    sql = "INSERT INTO message (appid, authorUserId, targetUserId, message, unixtime_ms) VALUES (%s, %s, %s, %s, %s)"
    cursor.execute(sql, (appId, userId, targetUserId, message, unixtime_ms))
    db.commit()
    return STATUS_OK
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return STATUS_INTERNAL_ERROR
 


def get_userid_for_nickname(appId, nickname, addr, db):
  threadName = threading.currentThread().name    
  cursor = db.cursor()
  try:
    sql = "SELECT userid FROM user where nickname = %s;"
    cursor.execute(sql, (nickname))
    results = cursor.fetchone()
    if results == None:
      print ("<{threadName}-{addr}> nickname {nickname} is not found in db. Returning internal error".format(**locals()))
      return None
    else:
      nickname = results[0]
      return nickname
  except IntegrityError as e:
    print ("Caught an IntegrityError:"+str(e))
    return None


def handle_get_message(appId, userId, messageId, addr, db):
  threadName = threading.currentThread().name  
  if not(isValidUserIdForApp(userId, appId, db)):
    response = build_response(STATUS_UNREGISTERED_USERID)
    print ("<{threadName}-{addr}>: userId {userId} is not registered with app {appId} in db. Response {response}".format(**locals()))
    return response 
  cursor = db.cursor()
  try:  
    sql = "select messageId from message where appId = %s and targetUserId like %s order by messageId"
    cursor.execute(sql, (appId, userId,))
    results = cursor.fetchall()
    if results == None:
      print ("<{threadName}-{addr}> failed to locate list of messages for userId {userId} in appId {appId} in db. results {results}".format(**locals()))
      response = build_response(STATUS_INTERNAL_ERROR)
      return response
    else:
      messageIds = results
      messageCount = len(messageIds)
      print ("<{threadName}-{addr}> userId has {messageCount} messages for appId {appId} in db".format(**locals()))
      if messageId <= messageCount:
        actualMessageId = messageIds[messageId-1]
        sql = "select message,authorUserId from message where messageId = %s"
        cursor.execute(sql, (actualMessageId))
        results = cursor.fetchall()
        if results == None:
          print ("<{threadName}-{addr}> failed to locate messageId {messageId} in db. results {results}".format(**locals()))
          response = build_response(STATUS_INTERNAL_ERROR)
          return response
        else:
          message = results[0][0]
          messageLen = len(message)
          bMessage = bytearray(messageLen) # \x00 filled
          bMessage[0:messageLen] = message.encode()
          bStatus = bytearray(1)
          bStatus[0] = STATUS_GET_MESSAGE_OK
          bLen = bytearray(1)
          bLen[0]=messageLen
          authorUserId = results[0][1]
          authorNick = lookup_nick_for_userid(authorUserId,db,addr)
          zAuthorNick = zeroPad(authorNick,20)
          if authorNick == None:
              print ("<{threadName}-{addr}> failed to lookup nick for user {userId}".format(**locals()))
              response = build_response(STATUS_INTERNAL_ERROR)
              return response
          print ("<{threadName}-{addr}> returning message of len {messageLen} with messageid {messageId} from author {authorNick} for user {userId}".format(**locals()))
          response = bytes(bytearray(bStatus + zAuthorNick + bLen + bMessage))
          return response
      else:
          print ("<{threadName}-{addr}> invalid messageid {messageId} for user {userId}".format(**locals()))
          response = build_response(STATUS_INVALID_MESSAGE_ID)
          return response
  except IntegrityError as e:
    print ("<{threadName}-{addr}> Caught an IntegrityError:"+str(e))
    response = build_response(STATUS_INTERNAL_ERROR)
    return response

def lookup_nick_for_userid(userId,db,addr):
  threadName = threading.currentThread().name    
  cursor = db.cursor()  
  try:
    sql = "select nickname from user where userId = %s"
    cursor.execute(sql, (userId,))
    results = cursor.fetchone()
    if results == None:
      print ("<{threadName}-{addr}> failed to locate nick of userId {userId} in db".format(**locals()))
      return None
    else:
      nick = results[0] 
      print ("<{threadName}-{addr}> userId {userId} has nick {nick} in db".format(**locals()))
      return nick
  except IntegrityError as e:
    print ("<{threadName}-{addr}> Caught an IntegrityError:"+str(e))
    return None

def handle_get_message_count(appId, userId, addr, db):
  threadName = threading.currentThread().name   
  if not(isValidUserIdForApp(userId, appId, db)):
    response = build_response(STATUS_UNREGISTERED_USERID)
    print ("<{threadName}-{addr}>: userId {userId} is not registered with app {appId} in db. Response {response}".format(**locals()))
    return response 
  cursor = db.cursor()
  try:
    sql = "select count(*) from message where appId = %s and targetUserId like %s order by messageId"
    cursor.execute(sql, (appId, userId,))
    results = cursor.fetchone()
    if results == None:
      print ("<{threadName}-{addr}> failed to locate count of messages for userId {userId} in appId {appId} in db. results {results}".format(**locals()))
      response = build_response(STATUS_INTERNAL_ERROR)
      return response
    else:
      messageCount = results[0] 
      print ("<{threadName}-{addr}> userId has {messageCount} messages for appId {appId} in db".format(**locals()))
      response = bytes([STATUS_COUNT_OK] + list(messageCount.to_bytes(2, byteorder="little"))) # todo OverflowError raised if num > 2 bytes
      return response
  except IntegrityError as e:
    print ("<{threadName}-{addr}> Caught an IntegrityError:"+str(e))
    response = build_response(STATUS_INTERNAL_ERROR)
    return response


def handle_check_registered_nickname(appId, userId, nickname, addr, db):
  threadName = threading.currentThread().name    

  if nickname == None or len(nickname) == 0:
    response = build_response(STATUS_MISSING_NICKNAME)
    print("<{threadName}-{addr}>: MISSING nickname for check registered nickname cmd. Response: {response}".format(**locals()))
    return response

  print("<{threadName}-{addr}>: checking nickname")
  status = do_check_registered_nickname_for_app(appId, userId, nickname, addr, db)
  response = build_response(status)
  print("<{threadName}-{addr}>: response: {response}".format(**locals()))
  return response
 

def do_check_registered_nickname_for_app(appId, userId, nickname, addr, db):
  threadName = threading.currentThread().name    
  print ("<{threadName}-{addr}> checking if nick {nickname} is registered for app {appId} in db ".format(**locals()))
  cursor = db.cursor()
  try:
    sql = "SELECT user.nickname FROM user INNER JOIN app_user ON user.userid = app_user.userid and user.nickname like %s and app_user.appid = %s;"
    cursor.execute(sql, (nickname, appId,))
    results = cursor.fetchone()
    print(results)
    if results == None:
      print ("<{threadName}-{addr}> nickname {nickname} is not registered for appId {appId} in db".format(**locals()))
      return STATUS_UNREGISTERED_NICKNAME
    else:
      print ("<{threadName}-{addr}> nickname {nickname} is registered for appId {appId} in db".format(**locals()))
      return STATUS_OK
  except IntegrityError as e:
      print ("<{threadName}-{addr}> Caught an IntegrityError:"+str(e))
      return STATUS_INTERNAL_ERROR


def isValidUserId(userId, db):
  cursor = db.cursor()
  sql = "select * from mbox.user where userId = %s"
  cursor.execute(sql, (userId))
  results = cursor.fetchone()
  return results != None


def isValidUserIdForApp(userId, appId, db):
  cursor = db.cursor()
  sql = "select * from mbox.app_user where userId = %s and appid = %s"
  cursor.execute(sql, (userId, appId))
  results = cursor.fetchone()
  return results != None


def handle_register(appId, userId, addr, db):
  threadName = threading.currentThread().name    
  alreadyRegistered = False
  cursor = db.cursor()
  sql = "select * from mbox.app_user where userId = %s and appid = %s"
  cursor.execute(sql, (userId, appId))
  results = cursor.fetchone()
  #print(results)

  if results == None:
    print ("<{threadName}-{addr}>: userId not in app_user for app {appId} in db".format(**locals()))
    registeredOk = do_register_user(appId, userId, addr, cursor)
    if not(registeredOk):
      response = build_response(STATUS_INTERNAL_ERROR)
      print("<{threadName}-{addr}>: REGISTER failed. Response: {response}".format(**locals()))
      return response
  else:
      print ("<{threadName}-{addr}>: userId {userId} already in db for app {appId}".format(**locals()))
      alreadyRegistered = True

  sql = "select nickname from mbox.user where userId like %s"
  cursor.execute(sql, (userId))
  nickname = cursor.fetchone()[0]
  print ("<{threadName}-{addr}>: userId {userId} has nickname {nickname} in db".format(**locals()))
  zNickname = zeroPad(nickname,20)
  statusBytearray = bytearray(1)
  statusBytearray[0] = STATUS_USER_ALREADY_REGISTERED if alreadyRegistered else STATUS_REGISTER_OK
  response = bytes(bytearray(statusBytearray + zNickname))
  print("<{threadName}-{addr}>: response: {response}".format(**locals()))
  return response

 
def zeroPad(s, length):
  if(len(s) == length):
    return s
  elif (len(s) > length):
    return s[:length]
  else:
    arr = bytearray(length) # \x00 filled
    arr[0:len(s)] = s.encode()
    return arr


def do_register_user(appId, userId, addr, cursor):
  threadName = threading.currentThread().name    
  print ("<{threadName}-{addr}> userId {userId} is not yet registered for app {appId} in db ".format(**locals()))
  try:
      sql = "INSERT INTO app_user (appid, userId) VALUES (%s, %s)"
      cursor.execute(sql, (appId, userId,))
      db.commit()
      return True
  except IntegrityError as e:
      print ("<{threadName}-{addr}>: Caught a IntegrityError:"+str(e))
      return False


def build_response(status):
  rStatus=[status]
  response=bytes(rStatus)
  return response

# Open database connection
db = pymysql.connect("localhost","mboxserver","catfishbookwormzebra","mbox" )

s = socket.socket()        
port = 8080                

print ('Server started. Waiting for clients...')

s.bind(('', port))        # '' for all interfaces
s.listen(1000)                

while True:
   c, addr = s.accept()    
   x = threading.Thread(target=on_new_client, args=(c, addr, db))
   x.start()

s.close()
