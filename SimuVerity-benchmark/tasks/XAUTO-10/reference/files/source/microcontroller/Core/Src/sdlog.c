/*
 * sdlog.c
 *
 *  Created on: Apr 19, 2023
 *      Author: Isaak
 */

#include "sdlog.h"

//DECLARATION OF GLOBAL VARIABLES

FATFS file_system;
FIL file;
FILINFO file_info;
FRESULT file_result;
UINT bytes_to_write, bytes_read;
FATFS * file_system_pointer;
DWORD free_cluster;
uint32_t total_space, free_space;

FRESULT sd_mount(const TCHAR * sd_path){
	file_result = f_mount(&file_system, sd_path, 1);
	if(file_result != FR_OK)
		perror("!!!! ERROR !!!! SD CARD NOT MOUNTED !!!!");
	printf("SD card mounted successfully");
	return file_result;
}

FRESULT sd_unmount(const TCHAR * sd_path){
	file_result = f_mount(NULL, sd_path, 0);
	if(file_result == FR_OK)
		printf("SD card has been unmounted successfully");
	perror("!!!! ERROR !!!! SD CARD STILL MOUNTED !!!!");
	return file_result;
}

FRESULT sd_scan  (char * path){
	DIR directory;
	UINT i;
	char * pathway = malloc(20 * sizeof (char));
	sprintf (pathway, "%s", path);
	//Open directory
	file_result = f_opendir(&directory, pathway);
	if (file_result == FR_OK){
		for (;;){
			//Read directory
	        file_result = f_readdir(&directory, &file_info);
	        //Break on errors
	        if (file_result != FR_OK || file_info.fname[0] == 0) break;
	        //A directory is found
	        if (file_info.fattrib & AM_DIR){
	            if (!(strcmp ("SYSTEM~1", file_info.fname))) continue;
	            char * buf = malloc(30 * sizeof(char));
	            sprintf (buf, "Dir: %s\r\n", file_info.fname);
	            printf(buf);
	            free(buf);
	            i = strlen(pathway);
	            sprintf(&pathway[i], "/%s", file_info.fname);
	            //Enter the directory
	            file_result = sd_scan(pathway);
	            if (file_result != FR_OK) break;
	            pathway[i] = 0;
	        //A file is found
	        } else {
	        	char * buf = malloc(30 * sizeof(char));
	            sprintf(buf,"File: %s/%s\n", pathway, file_info.fname);
	            printf(buf);
	            free(buf);
	        }
	     }
	     f_closedir(&directory);
	}
	free(pathway);
	return file_result;
}



FRESULT sd_format(void){
	DIR directory;
	char * path = malloc(20 * sizeof (char));
	sprintf (path, "%s","/");
	//Open Directory
	file_result = f_opendir(&directory, path);
	if (file_result == FR_OK){
	    for (;;)
	    {
	    	//Read directory
	        file_result = f_readdir(&directory, &file_info);
	        //Break on errors
	        if (file_result != FR_OK || file_info.fname[0] == 0) break;
	        //If file_info is a directory
	        if (file_info.fattrib & AM_DIR) {
	        	if (!(strcmp ("SYSTEM~1", file_info.fname))) continue;
	            file_result = f_unlink(file_info.fname);
	            if (file_result == FR_DENIED) continue;
	        } else{
	        	//If file_info is a file
	            file_result = f_unlink(file_info.fname);
	        }
	    }
	    f_closedir(&directory);
	}
	free(path);
	return file_result;
}

FRESULT sd_write (char * name, char * to_write){
	file_result = f_stat (name, &file_info);
	//Check if file exists	``
	if (file_result != FR_OK)
	{
		char * buf = malloc(100 * sizeof(char));
		sprintf (buf, "!!!! ERROR !!!! *%s* does not exist !!!!\n", name);
		printf (buf);
	    free(buf);
	    return file_result;
	}

	else
	{
	    //Create a file with R/W Permissions
	    file_result = f_open(&file, name, FA_OPEN_EXISTING | FA_WRITE);
	    if (file_result != FR_OK)
	    {
	    	char * buf = malloc(100 * sizeof(char));
	    	sprintf (buf, "!!!! ERROR !!!! No. %d in opening file *%s* !!!!\n", file_result, name);
	    	printf(buf);
	        free(buf);
	        return file_result;
	    }

	    else
	    {
	    	file_result = f_write(&file, to_write, strlen(to_write), &bytes_to_write);
	    	if (file_result != FR_OK)
	    	{
	    		char * buf = malloc(100 * sizeof(char));
	    		sprintf (buf, "!!!! ERROR !!!!  No. %d while writing to the FILE *%s* !!!!\n", file_result, name);
	    		printf(buf);
	    		free(buf);
	    	}

	    	//Close the file
	    	file_result = f_close(&file);
	    	if (file_result != FR_OK)
	    	{
	    		char * buf = malloc(100 * sizeof(char));
	    		sprintf (buf, "!!!! ERROR !!!! No. %d in closing file *%s* after writing it !!!!\n", file_result, name);
	    		printf(buf);
	    		free(buf);
	    	}
	    	else
	    	{
	    		char *buf = malloc(100 * sizeof(char));
	    		sprintf (buf, "!!!! ERROR !!!! File *%s* is WRITTEN and CLOSED successfully !!!!\n", name);
	    		printf(buf);
	    		free(buf);
	    	}
	    }
	    return file_result;
	}
}

//ReadFile
FRESULT sd_read(char * name){
	//Check to see if file exists
	file_result = f_stat (name, &file_info);
	if (file_result != FR_OK){
		char * buf = malloc(100 * sizeof(char));
		sprintf (buf, "!!!! ERROR !!!! *%s* does not exists !!!!\n", name);
		printf (buf);
		free(buf);
		return file_result;
		} else {
			// Open file to read
			file_result = f_open(&file, name, FA_READ);
			if (file_result != FR_OK){
				char * buf = malloc(100 * sizeof(char));
				sprintf (buf, "!!!! ERROR !!!! No. %d in opening file *%s* !!!!\n", file_result, name);
				printf(buf);
			    free(buf);
			    return file_result;
			}

			//Read data from file
			char *buffer = malloc(sizeof(f_size(&file)));
			file_result = f_read (&file, buffer, f_size(&file), &bytes_read);
			if (file_result != FR_OK)
			{
				char *buf = malloc(100 * sizeof(char));
				free(buffer);
			 	sprintf (buf, "!!!! ERROR !!!! No. %d in reading file *%s* !!!!\n", file_result, name);
			 	printf(buffer);
			  	free(buf);
			} else {
				printf(buffer);
				free(buffer);
				//Close the file
				file_result = f_close(&file);
				if (file_result != FR_OK)
				{
					char *buf = malloc(100 * sizeof(char));
					sprintf (buf, "!!!! ERROR !!!! No. %d in closing file *%s* !!!!\n", file_result, name);
					printf(buf);
					free(buf);
				} else {
					char *buf = malloc(100 * sizeof(char));
					sprintf (buf, "FILE *%s* CLOSE SUCCESS\n", name);
					printf(buf);
					free(buf);
				}
			}
		return file_result;
	}
}

//Check if SD card is saving
void sd_check(FRESULT fresult){
	if(fresult != FR_OK)
		printf("!!!! ERROR !!!!! DATA IS NOT SAVING !!!!");
}


//CreateFIle
FRESULT file_create(char * name){
	file_result = f_stat (name, &file_info);
	if (file_result == FR_OK){
		char * buf = malloc(100 * sizeof(char));
		sprintf (buf, "!!!! ERROR !!!! *%s* already exists!!!!\n use Update_File !!!!\n",name);
		printf(buf);
		free(buf);
		   return file_result;
	}else{
		file_result = f_open(&file, name, FA_CREATE_ALWAYS|FA_READ|FA_WRITE);
		if (file_result != FR_OK){
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "!!!! ERROR !!!! No. %d in creating file *%s* !!!!\n", file_result, name);
			printf(buf);
			free(buf);
			   return file_result;
		}else{
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "*%s* CREATION SUCCESS\n", name);
			printf(buf);
			free(buf);
		}
		file_result = f_close(&file);
		if (file_result != FR_OK){
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "!!!! ERROR !!!! in closing file *%s* !!!!\n", name);
			printf(buf);
			free(buf);
		}
		else
		{
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "File *%s* CLOSED successfully\n", name);
			printf(buf);
			free(buf);
		}
	}
	   return file_result;
}

//File Update
FRESULT file_update(char * name, char * data){
	//Check if file exists
	file_result = f_stat (name, &file_info);
	if (file_result != FR_OK){
		char * buf = malloc(100 * sizeof(char));
		sprintf (buf, "ERROR!!! *%s* does not exists\n", name);
		printf (buf);
		free(buf);
		return file_result;
	} else {
		//Create file with RW permissions
		file_result = f_open(&file, name, FA_OPEN_APPEND | FA_WRITE);
		if (file_result != FR_OK) {
			char * buf = malloc(100 * sizeof(char));
		    sprintf (buf, "ERROR!!! No. %d in opening file *%s*\n", file_result, name);
		    printf(buf);
		    free(buf);
		    return file_result;
		}
		//Write text
		file_result = f_write(&file, data, strlen (data), &bytes_to_write);
		if (file_result != FR_OK){
			char * buf = malloc(100 * sizeof(char));
		    sprintf (buf, "ERROR!!! No. %d in writing file *%s*\n", file_result, name);
		    printf(buf);
		    free(buf);
		} else {
		    char * buf = malloc(100 * sizeof(char));
		    sprintf (buf, "*%s* UPDATED successfully\n", name);
		    printf(buf);
		    free(buf);
		}
		//Close file
		file_result = f_close(&file);
		if (file_result != FR_OK){
		    char * buf = malloc(100 * sizeof(char));
		    sprintf (buf, "ERROR!!! No. %d in closing file *%s*\n", file_result, name);
		    printf(buf);
		    free(buf);
		} else {
		    char * buf = malloc(100 * sizeof(char));
		    sprintf (buf, "File *%s* CLOSED successfully\n", name);
		    printf(buf);
		    free(buf);
		}
	}
	return file_result;
}

//RemoveFile
FRESULT file_remove(char * name){
	file_result = f_stat (name, &file_info);
	if (file_result != FR_OK){
		char * buf = malloc(100 * sizeof(char));
		sprintf (buf, "!!!! ERROR !!!! *%s* does not exist !!!!\n", name);
		printf(buf);
		free(buf);
		return file_result;
	} else{
		file_result = f_unlink(name);
		if (file_result == FR_OK){
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "*%s* SUCCESSFULLY REMOVED\n", name);
			printf(buf);
			free(buf);
		}else{
			char * buf = malloc(100 * sizeof(char));
			sprintf (buf, "!!!! ERROR !!!! REMOVING *%s* !!!!\n", name);
			printf(buf);
			free(buf);
		}
	}
	return file_result;
}

FRESULT create_directory(char * directory_name){
	file_result = f_mkdir(directory_name);
	if (file_result == FR_OK){
		char * buf = malloc(100 * sizeof(char));
	    sprintf (buf, "*%s* has been successfully created as a directory\n", directory_name);
	    printf(buf);
	    free(buf);
	} else {
	    char * buf = malloc(100 * sizeof(char));
	    sprintf (buf, "!!!! ERROR !!!! DIRECTORY NOT CREATED !!!!\n");
	    printf(buf);
	    free(buf);
	}
	return file_result;
}

void sd_space_check(void){
	f_getfree("", &free_cluster, &file_system_pointer);

	total_space = (uint32_t)((file_system_pointer->n_fatent - 2) * file_system_pointer->csize * 0.5);

	char * buf = malloc(30 * sizeof(char));
	sprintf (buf, "Total SD card size: %lu\n",total_space);
	printf(buf);
	free(buf);

	free_space = (uint32_t)(free_cluster * file_system_pointer->csize * 0.5);

	buf = malloc(30 * sizeof(char));
	sprintf (buf, "Remaining SD card space: %lu\n",free_space);
	printf(buf);
	free(buf);
}



