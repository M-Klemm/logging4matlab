classdef logging < handle
  %LOGGING Simple logging framework.
  %
  % Author:
  %     Dominique Orban <dominique.orban@gmail.com>
  % Heavily modified version of 'log4m': http://goo.gl/qDUcvZ
  %

  properties (Constant)
    ALL      = int8(0);
    TRACE    = int8(1);
    DEBUG    = int8(2);
    INFO     = int8(3);
    WARNING  = int8(4);
    ERROR    = int8(5);
    CRITICAL = int8(6);
    OFF      = int8(7);

    colors_terminal = containers.Map(...
      {'normal', 'red', 'green', 'yellow', 'blue', 'brightred'}, ...
      {'%s', '\033[31m%s\033[0m', '\033[32m%s\033[0m', '\033[33m%s\033[0m', ...
       '\033[34m%s\033[0m', '\033[1;31m%s\033[0m'});

    level_colors = containers.Map(...
      {logging.logging.INFO, logging.logging.ERROR, logging.logging.TRACE, ...
       logging.logging.WARNING, logging.logging.DEBUG, logging.logging.CRITICAL}, ...
       {'normal', 'red', 'green', 'yellow', 'blue', 'brightred'});

    levels = containers.Map(...
      {logging.logging.ALL,      logging.logging.TRACE,   logging.logging.DEBUG, ...
       logging.logging.INFO,     logging.logging.WARNING, logging.logging.ERROR, ...
       logging.logging.CRITICAL, logging.logging.OFF}, ...
      {'ALL', 'TRACE', 'DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL', 'OFF'});
  end
  
  properties (SetAccess=immutable)
    level_numbers;
    level_range;
  end

  properties (SetAccess=protected)
    name;
    fullpath = 'logging.log';  % Default log file
    logfmt = '%-s %-23s %-8s %s\n';
    logfid = -1;
    logcolors = logging.logging.colors_terminal;
    using_terminal;
    maxLogFileSize = 1024^3; %max logifle size in bytes, default: 10 MB, set to <=0 for unlimited logfile size
  end

  properties (Hidden,SetAccess=protected)
    datefmt_ = 'yyyy-mm-dd HH:MM:SS,FFF';
    logLevel_ = logging.logging.INFO;
    commandWindowLevel_ = logging.logging.INFO;
  end
  
  properties (Dependent)
    datefmt;
    logLevel;
    commandWindowLevel;
  end

  methods(Static)
    function [name, line] = getCallerInfo(self)
      
      if nargin > 0 && self.ignoreLogging()
          name = [];
          line = [];
          return
      end
      [ST, ~] = dbstack();
      offset = min(size(ST, 1), 3);
      name = ST(offset).name;
      line = ST(offset).line;
    end
  end

  methods

    function setFilename(self, logPath)
      logFolder = fileparts(logPath);
      if(~isfolder(logPath))
        [status, message, ~] = mkdir(logFolder);
        if(~status)
          warning('Could not create folder for logfile: %s\n%s',logFolder,message);
        end
      end
      [self.logfid, message] = fopen(logPath, 'a+');

      if self.logfid < 0
        warning(['Problem with supplied logfile path: ' message]);
        self.logLevel_ = logging.logging.OFF;
      end

      self.fullpath = logPath;
    end
    
    function setMaxFileSize(self,val)
      %set the max size of the log file in bytes (at least 1 kB)
      if(isnumeric(val) && isscalar(val))
        self.maxLogFileSize = max(1024,val);
        self.checkLogFileSize();
      end
    end

    function setCommandWindowLevel(self, level)
      self.commandWindowLevel = level;
    end

    function setLogLevel(self, level)
      self.logLevel = level;
    end
    
    function tf = ignoreLogging(self)
        tf = self.commandWindowLevel_ == self.OFF && self.logLevel_ == self.OFF;
    end

    function trace(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.TRACE, caller_name, varargin{:});
    end

    function debug(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.DEBUG, caller_name, varargin{:});
    end

    function info(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.INFO, caller_name, varargin{:});
    end

    function warn(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.WARNING, caller_name, varargin{:});
    end

    function error(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.ERROR, caller_name, varargin{:});
    end

    function critical(self, varargin)
      [caller_name, ~] = self.getCallerInfo(self);
      self.writeLog(self.CRITICAL, caller_name, varargin{:});
    end

    function self = logging(name, varargin)
      levelkeys = self.levels.keys;
      self.level_numbers = containers.Map(...
          self.levels.values, levelkeys);
      levelkeys = cell2mat(self.levels.keys);
      self.level_range = [min(levelkeys), max(levelkeys)];
      
      p = inputParser();
      p.addRequired('name', @ischar);
      p.addParameter('path', '', @ischar);
      p.addParameter('logLevel', self.logLevel);
      p.addParameter('commandWindowLevel', self.commandWindowLevel);
      p.addParameter('datefmt', self.datefmt_);
      p.parse(name, varargin{:});
      r = p.Results; 
      
      self.name = r.name;
      self.commandWindowLevel = r.commandWindowLevel;
      self.datefmt = r.datefmt;
      if ~isempty(r.path)
        self.setFilename(r.path);  % Opens the log file.
        self.logLevel = r.logLevel;
      else
        self.logLevel_ = logging.logging.OFF;
      end
      % Use terminal logging if swing is disabled in matlab environment.
      swingError = javachk('swing');
      self.using_terminal = (~ isempty(swingError) && strcmp(swingError.identifier, 'MATLAB:javachk:thisFeatureNotAvailable')) || ~desktop('-inuse');
    end

    function delete(self)
      if self.logfid > -1
        fclose(self.logfid);
      end
    end
    
    function status = checkLogFileSize(self, newLineLen)
        %check size of log file and reduce if necessary
        if(nargin == 1)
            newLineLen = 0;
        end
        status = true;
        if(self.maxLogFileSize > 0)
            %check file size
            info = dir(self.fullpath);
            if(~isempty(info) && isstruct(info) && isfield(info,'bytes'))
                target = info.bytes + newLineLen - self.maxLogFileSize;
                if(target > 0)
                    %log file has grown too big -> delete oldest lines until the new line fits
                    frewind(self.logfid);
                    while target > 0
                        tmpLine = fgetl(self.logfid);
                        if(isempty(tmpLine) || isnumeric(tmpLine) && isscalar(tmpLine) && tmpLine == -1)
                            break
                        end
                        target = target - length(tmpLine);
                    end
                    newLog = fread(self.logfid); %read the data we want to keep
                    fclose(self.logfid);
                    %overwrite old logfile with empty file - this is more reliable than delete
                    tmp = '';
                    save(self.fullpath,'tmp','-ASCII');
                    self.setFilename(self.fullpath);
                    if(self.logfid < 0)
                        %something went wrong
                        status = false;
                        return
                    end
                    fwrite(self.logfid, newLog); %write the new logfile
                end
            end
        end
    end

    function writeLog(self, level, caller, message, varargin)        
      level = self.getLevelNumber(level);
      if self.commandWindowLevel_ <= level || self.logLevel_ <= level
        timestamp = datestr(now, self.datefmt_);
        levelStr = logging.logging.levels(level);
        logline = sprintf(self.logfmt, caller, timestamp, levelStr, self.getMessage(message, varargin{:}));
      end

      if self.commandWindowLevel_ <= level
        if self.using_terminal
          level_color = self.level_colors(level);
        else
          level_color = self.level_colors(logging.logging.INFO);
        end
        fprintf(self.logcolors(level_color), logline);
      end

      if self.logLevel_ <= level && self.logfid > -1
        %make sure the new logline will fit into the logifle
        if(~self.checkLogFileSize(length(logline)))
            %something went wrong
            return
        end
        fprintf(self.logfid, '%s', logline);
      end
    end        
    
    function set.datefmt(self, fmt)
      try
        datestr(now(), fmt);
      catch
        error('Invalid date format');
      end
      self.datefmt_ = fmt;
    end

    function fmt = get.datefmt(self)
      fmt = self.datefmt_;
    end
    
    function set.logLevel(self, level)
      level = self.getLevelNumber(level);
      if level > logging.logging.OFF || level < logging.logging.ALL
        error('invalid logging level');
      end
      self.logLevel_ = level;
    end
    
    function level = get.logLevel(self)
      level = self.logLevel_;
    end
    
    function set.commandWindowLevel(self, level)
      self.commandWindowLevel_ = self.getLevelNumber(level);
    end
    
    function level = get.commandWindowLevel(self)
      level = self.commandWindowLevel_;
    end
        
        
  end
  
  methods (Hidden)
    function level = getLevelNumber(self, level)
    % LEVEL = GETLEVELNUMBER(LEVEL)
    %
    % Converts character-based level names to level numbers
    % used internally by logging.
    %
    % If given a number, it makes sure the number is valid
    % then returns it unchanged.
    %
    % This allows users to specify levels by name or number.
      if isinteger(level) && self.level_range(1) <= level && level <= self.level_range(2)
        return
      else
        level = self.level_numbers(level);
      end
    end
      
    function message = getMessage(~, message, varargin)
    
      if isa(message, 'function_handle')
        message = message();
      end
      
      if nargin > 2
        message = sprintf(message, varargin{:});
      end
      
      if(iscell(message))
        [rows, ~] = size(message);
        if rows > 1
          message = sprintf('\n %s', evalc('disp(message)'));
        end
      elseif(ischar(message))
          %remove trailing newline characters
          idx = false(size(message));
          idx(regexp(message, '[\r\n]')) = true;
          idx = find(~idx,length(message),'last');
          if(~isempty(idx))
              message = message(1:idx(end));
          end
          %replace remaining newline characters with ;
          message(regexp(message, '[\r\n]')) = ';';
      end
      %to do: add string handling
    end
  
 end
end
